// Package engine orchestrates the template generation pipeline.
package engine

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
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

// Execute runs the full generation pipeline:
//  1. Load manifest from manifestPath
//  2. Discover templates from outputRoot
//  3. Phase0 — gather prompts, detect conflicts
//  4. Phase1 — stage to temp, render, inject
//  5. Phase2 — atomic commit to outputRoot
//  6. Run post_generate hooks
//
// On any phase failure, staged files are rolled back and an error is returned.
func (e *Engine) Execute(ctx context.Context, manifestPath, outputRoot string) (*Result, error) {
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

	// Step 3: Phase0 — gather prompts and detect conflicts
	// Use empty prompt values for now; in a full CLI these would come from the user
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

	// Step 4: Phase1 — stage, render, inject
	phase1Input := phase1.Phase1Input{
		ResolvedValues: phase0Output.ResolvedValues,
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

	// Step 5: Phase2 — atomic commit
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

	// Step 6: Run post_generate hooks
	if err := hooks.ExecuteHooks(e.Hooks, "post_generate"); err != nil {
		return nil, fmt.Errorf("post_generate hook failed: %w", err)
	}

	return &Result{
		CommittedFiles: phase2Output.CommittedFiles,
		InjectionLog:   phase1Output.InjectionLog,
	}, nil
}
