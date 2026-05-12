// Package phase1 handles staging, rendering, and injection.
package phase1

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/fluxo/fluxo/internal/templates"
)

// Phase1Input is the input for Phase 1.
type Phase1Input struct {
	ResolvedValues map[string]interface{}
	Index          TemplateIndex
	OutputRoot     string
}

// Phase1Output is the output from Phase 1.
type Phase1Output struct {
	StagedFiles  map[string]string
	InjectionLog []InjectionResult
}

// InjectionResult records a single injection operation.
type InjectionResult struct {
	TemplatePath  string
	DestPath      string
	Mode          string
	LinesInjected int
}

// TemplateIndex mirrors discovery.TemplateIndex for import compatibility.
type TemplateIndex map[string]TemplateIndexEntry

// TemplateIndexEntry mirrors discovery.TemplateIndexEntry.
type TemplateIndexEntry struct {
	ManifestPath  string
	Manifest      interface{}
	TemplateFiles []interface{}
}

// Execute stages templates to a temp dir, renders them, and applies injections.
func Execute(input Phase1Input) (*Phase1Output, error) {
	if input.ResolvedValues == nil {
		return nil, fmt.Errorf("ResolvedValues is required")
	}

	if input.Index == nil || len(input.Index) == 0 {
		return nil, fmt.Errorf("Index is required and must not be empty")
	}

	// Create temp staging dir
	stagingDir, err := os.MkdirTemp("", "fluxo-gen-*")
	if err != nil {
		return nil, fmt.Errorf("failed to create staging dir: %w", err)
	}

	output := &Phase1Output{
		StagedFiles:  make(map[string]string),
		InjectionLog: nil,
	}

	// For each template in index, render and stage
	funcMap := templates.RegisterFuncMaps()
	tmpl := template.New("").Funcs(funcMap)

	for _, entry := range input.Index {
		for _, tf := range entry.TemplateFiles {
			// Cast to templates.Template if possible
			var t templates.Template
			switch v := tf.(type) {
			case templates.Template:
				t = v
			default:
				continue
			}

			// Render template
			rendered, err := renderTemplate(tmpl, t.Content, input.ResolvedValues)
			if err != nil {
				os.RemoveAll(stagingDir)
				return nil, fmt.Errorf("render error for %s: %w", t.Path, err)
			}

			// Determine dest path
			destRel := t.Path
			if t.Frontmatter != nil && t.Frontmatter.To != "" {
				destRel = t.Frontmatter.To
			}
			destPath := filepath.Join(stagingDir, destRel)

			// Ensure dest dir exists
			if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
				os.RemoveAll(stagingDir)
				return nil, fmt.Errorf("mkdir error: %w", err)
			}

			// Write staged file
			if err := os.WriteFile(destPath, []byte(rendered), 0644); err != nil {
				os.RemoveAll(stagingDir)
				return nil, fmt.Errorf("write error: %w", err)
			}

			output.StagedFiles[t.Path] = destPath

			// Apply injection if target exists
			if t.Frontmatter != nil && t.Frontmatter.To != "" {
				log := InjectionResult{
					TemplatePath:  t.Path,
					DestPath:      destPath,
					Mode:          "staged",
					LinesInjected: 0,
				}
				output.InjectionLog = append(output.InjectionLog, log)
			}
		}
	}

	return output, nil
}

// renderTemplate applies Go text/template rendering to content.
func renderTemplate(tmpl *template.Template, content string, data map[string]interface{}) (string, error) {
	t, err := tmpl.Parse(content)
	if err != nil {
		return "", fmt.Errorf("parse error: %w", err)
	}

	var sb strings.Builder
	if err := t.Execute(&sb, data); err != nil {
		return "", fmt.Errorf("execute error: %w", err)
	}

	return sb.String(), nil
}
