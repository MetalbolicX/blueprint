// Package engine orchestrates the template generation pipeline.
package engine

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/fluxo/fluxo/internal/discovery"
	"github.com/fluxo/fluxo/internal/hooks"
	"github.com/fluxo/fluxo/internal/manifest"
	"github.com/fluxo/fluxo/internal/phases/phase0"
	"github.com/fluxo/fluxo/internal/phases/phase1"
	"github.com/fluxo/fluxo/internal/phases/phase2"
	"github.com/fluxo/fluxo/internal/templates"
)

// HookConfig holds the hook scripts and execution parameters.
type HookConfig = hooks.HookConfig

// Context holds native template variables that are available in every template.
// These are merged with prompt values before rendering.
type Context struct {
	CWD          string            // current working directory
	ActionFolder string            // absolute path to the generator action folder (manifest directory)
	Name         string            // lowercase name (from --name or prompt)
	NamePascal   string            // PascalCase name
	Names        string            // plural lowercase name
	NamesPascal  string            // plural PascalCase name
	Attributes   map[string]string // CLI --key value flags
}

// Engine orchestrates template discovery, rendering, and commit.
type Engine struct {
	Funcmap template.FuncMap
	Hooks   HookConfig
}

// Result holds the output of a successful Execute call.
type Result struct {
	CommittedFiles []string
	InjectionLog   []phase1.InjectionResult
}

// NewEngine creates a new Engine with all FuncMaps registered.
func NewEngine(hookConfig HookConfig) *Engine {
	return &Engine{
		Funcmap: templates.RegisterFuncMaps(),
		Hooks:   hookConfig,
	}
}

// ContextInput holds the raw inputs needed to build a Context.
// This is passed to Execute to provide native variables to templates.
type ContextInput struct {
	CWD          string            // current working directory
	ManifestPath string            // path to the manifest.yaml (used to derive ActionFolder)
	Name         string            // name from CLI --name flag or prompt resolution
	Attributes   map[string]string // CLI --key value attributes
}

// ParseCLIAttributes parses --key value pairs from a slice of CLI arguments.
// For example: ["--name", "mycomponent", "--path", "/tmp"] → {"name": "mycomponent", "path": "/tmp"}
func ParseCLIAttributes(args []string) map[string]string {
	result := make(map[string]string)
	var currentKey string
	for _, arg := range args {
		if strings.HasPrefix(arg, "--") {
			currentKey = arg[2:]
		} else if currentKey != "" {
			result[currentKey] = arg
			currentKey = ""
		}
	}
	return result
}

// BuildContext creates a Context with all native variables populated.
func BuildContext(cwd, manifestDir, name string, cliAttrs map[string]string) Context {
	ctx := Context{
		CWD:          cwd,
		ActionFolder: manifestDir,
		Attributes:   cliAttrs,
	}

	// Generate name variants if name is provided
	if name != "" {
		ctx.Name = strings.ToLower(name)
		ctx.NamePascal = templates.PascalCase(name)
		ctx.Names = ctx.Name + "s"
		ctx.NamesPascal = ctx.NamePascal + "s"
	}

	return ctx
}

// toMap converts a Context to a map[string]interface{} for template rendering.
// Keys are: cwd, actionfolder, name, Name, names, Names, attributes.
func (c Context) toMap() map[string]interface{} {
	return map[string]interface{}{
		"cwd":          c.CWD,
		"actionfolder": c.ActionFolder,
		"name":         c.Name,
		"Name":         c.NamePascal,
		"names":        c.Names,
		"Names":        c.NamesPascal,
		"attributes":   c.Attributes,
	}
}

// Execute runs the full generation pipeline:
//  1. Load manifest from manifestPath
//  2. Discover templates from outputRoot
//  3. Build native context (cwd, actionfolder, name variants, attributes)
//  4. Phase0 — gather prompts, detect conflicts
//  5. Phase1 — stage to temp, render, inject
//  6. Phase2 — atomic commit to outputRoot
//  7. Run post_generate hooks
//
// On any phase failure, staged files are rolled back and an error is returned.
func (e *Engine) Execute(ctx context.Context, manifestPath, outputRoot string, contextInput ...ContextInput) (*Result, error) {
	// Step 1: Load manifest
	manifestData, err := os.ReadFile(manifestPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read manifest: %w", err)
	}

	m, err := manifest.Parse(manifestData)
	if err != nil {
		return nil, fmt.Errorf("failed to parse manifest: %w", err)
	}

	// Step 2: Discover templates
	// Use the parent directory of outputRoot as the discovery root,
	// or the directory containing the manifest if outputRoot is not available.
	discoverRoot := filepath.Dir(outputRoot)
	if discoverRoot == "." {
		discoverRoot = filepath.Dir(manifestPath)
	}

	index, err := discovery.Discover(discoverRoot)
	if err != nil {
		return nil, fmt.Errorf("template discovery failed: %w", err)
	}

	// Filter index to entries matching the manifest's classification
	entries := discovery.FindByClassification(index, m.Classification)
	if len(entries) == 0 {
		return nil, fmt.Errorf("no templates found for classification %q", m.Classification)
	}

	// Build a phase1-compatible index from filtered entries
	phase1Index := make(phase1.TemplateIndex)
	for _, entry := range entries {
		phase1Index[entry.ManifestPath] = phase1.TemplateIndexEntry{
			ManifestPath:  entry.ManifestPath,
			Manifest:      entry.Manifest,
			TemplateFiles: nil, // Templates resolved during phase1
		}
	}

	// Early validation: if no templates match, fail fast before Phase0
	if len(phase1Index) == 0 {
		return nil, fmt.Errorf("no templates found for classification %q", m.Classification)
	}

	// Step 3: Build native context variables
	var nativeCtx map[string]interface{}
	if len(contextInput) > 0 {
		ci := contextInput[0]
		manifestDir := filepath.Dir(ci.ManifestPath)
		name := ci.Name
		// If name not provided via context input, check attributes
		if name == "" {
			if n, ok := ci.Attributes["name"]; ok {
				name = n
			}
		}
		nativeCtx = BuildContext(ci.CWD, manifestDir, name, ci.Attributes).toMap()
	} else {
		// No context input provided — create minimal context with cwd only
		cwd, _ := os.Getwd()
		nativeCtx = BuildContext(cwd, filepath.Dir(manifestPath), "", nil).toMap()
	}

	// Step 4: Phase0 — gather prompts and detect conflicts
	promptValues := make(map[string]interface{})
	for _, p := range m.Prompts {
		if p.Default != nil {
			promptValues[p.Name] = p.Default
		}
	}

	phase0Input := phase0.Phase0Input{
		Index:        index,
		PromptValues: promptValues,
		Force:        false,
	}

	phase0Output, err := phase0.Execute(phase0Input)
	if err != nil {
		return nil, fmt.Errorf("phase0 failed: %w", err)
	}

	// Check for conflicts
	if len(phase0Output.Conflicts) > 0 {
		// Surface the first conflict as an error
		c := phase0Output.Conflicts[0]
		return nil, fmt.Errorf("conflict detected: %s", c.Source)
	}

	// Merge native context into resolved values (native vars override prompt defaults)
	// but prompts can override native if the same key exists (prompts are answers)
	for k, v := range phase0Output.ResolvedValues {
		nativeCtx[k] = v
	}
	// Also, CLI attributes can override prompts if same key (handled by BuildContext)
	// But we need to ensure CLI overrides are applied after prompts — handled below
	if len(contextInput) > 0 {
		// Re-apply CLI attributes override (they should override prompt values)
		for k, v := range contextInput[0].Attributes {
			nativeCtx[k] = v
		}
	}

	// Step 5: Phase1 — stage, render, inject
	phase1Input := phase1.Phase1Input{
		ResolvedValues: nativeCtx,
		Index:          phase1Index,
		OutputRoot:     outputRoot,
	}

	phase1Output, err := phase1.Execute(phase1Input)
	if err != nil {
		// Rollback staged files
		if phase1Output != nil && len(phase1Output.StagedFiles) > 0 {
			phase2.Rollback(phase1Output.StagedFiles)
		}
		return nil, fmt.Errorf("phase1 failed: %w", err)
	}

	// Step 6: Phase2 — atomic commit
	phase2Input := phase2.Phase2Input{
		StagedFiles: phase1Output.StagedFiles,
		OutputRoot:  outputRoot,
	}

	phase2Output, err := phase2.Execute(phase2Input)
	if err != nil {
		// Rollback staged files
		if len(phase2Input.StagedFiles) > 0 {
			phase2.Rollback(phase2Input.StagedFiles)
		}
		return nil, fmt.Errorf("phase2 failed: %w", err)
	}

	// Step 7: Run post_generate hooks
	if err := hooks.ExecuteHooks(e.Hooks, "post_generate"); err != nil {
		return nil, fmt.Errorf("post_generate hook failed: %w", err)
	}

	return &Result{
		CommittedFiles: phase2Output.CommittedFiles,
		InjectionLog:   phase1Output.InjectionLog,
	}, nil
}