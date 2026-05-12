// Package discovery traverses the filesystem to find and index templates.
package discovery

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/fluxo/fluxo/internal/manifest"
	"github.com/fluxo/fluxo/internal/templates"
)

// globPatterns matches template files in the files/ subdirectory.
var globPatterns = []string{"*.ejs.t", "*.tmpl"}

// TemplateIndex maps a manifest path to its indexed entry.
type TemplateIndex map[string]TemplateIndexEntry

// TemplateIndexEntry represents a single manifest and its associated templates.
type TemplateIndexEntry struct {
	ManifestPath  string
	Manifest      *manifest.Manifest
	TemplateFiles []templates.Template
}

// Discover traverses root recursively, finds all manifest.yaml files,
// parses them, and returns a TemplateIndex.
func Discover(root string) (TemplateIndex, error) {
	index := make(TemplateIndex)

	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return fmt.Errorf("walk error at %s: %w", path, err)
		}

		// Skip directories
		if info.IsDir() {
			return nil
		}

		// Only match manifest.yaml files
		if info.Name() != "manifest.yaml" {
			return nil
		}

		// Read the manifest file
		data, err := os.ReadFile(path)
		if err != nil {
			return fmt.Errorf("read error at %s: %w", path, err)
		}

		// Parse manifest
		m, err := manifest.Parse(data)
		if err != nil {
			return fmt.Errorf("manifest parse error at %s: %w", path, err)
		}

		// Load templates from files/ subdirectory
		templates, err := loadTemplates(filepath.Dir(path))
		if err != nil {
			// Skip invalid templates with warning, don't fail the whole discovery
			fmt.Fprintf(os.Stderr, "warning: skipping invalid templates in %s: %v\n", path, err)
		}

		entry := TemplateIndexEntry{
			ManifestPath:  path,
			Manifest:      m,
			TemplateFiles: templates,
		}

		index[path] = entry
		return nil
	})

	if err != nil {
		return nil, err
	}

	return index, nil
}

// FindByClassification filters the index to entries matching the given classification.
func FindByClassification(index TemplateIndex, classification string) []TemplateIndexEntry {
	var results []TemplateIndexEntry
	for _, entry := range index {
		if strings.TrimSpace(entry.Manifest.Classification) == classification {
			results = append(results, entry)
		}
	}
	return results
}

// loadTemplates reads template files from the files/ subdirectory relative to manifestDir.
// It returns a list of parsed Template structs or nil if the files/ directory doesn't exist.
func loadTemplates(manifestDir string) ([]templates.Template, error) {
	filesDir := filepath.Join(manifestDir, "files")
	info, err := os.Stat(filesDir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil // No files/ subdirectory — not an error
		}
		return nil, fmt.Errorf("stat files dir: %w", err)
	}
	if !info.IsDir() {
		return nil, nil
	}

	var result []templates.Template

	for _, pattern := range globPatterns {
		matches, err := filepath.Glob(filepath.Join(filesDir, pattern))
		if err != nil {
			return nil, fmt.Errorf("glob pattern %s: %w", pattern, err)
		}

		for _, match := range matches {
			tmpl, err := loadTemplate(match, manifestDir)
			if err != nil {
				// Skip invalid templates with warning — not an error
				fmt.Fprintf(os.Stderr, "warning: skipping invalid template %s: %v\n", match, err)
				continue
			}
			result = append(result, *tmpl)
		}
	}

	return result, nil
}

// loadTemplate reads a single template file, parses its frontmatter, and returns a Template struct.
// The path is relative to manifestDir for storage in Template.Path.
func loadTemplate(fullPath, manifestDir string) (*templates.Template, error) {
	data, err := os.ReadFile(fullPath)
	if err != nil {
		return nil, fmt.Errorf("read file: %w", err)
	}

	content := string(data)
	directives, remaining, err := templates.ParseFrontmatter(content)
	if err != nil {
		return nil, fmt.Errorf("parse frontmatter: %w", err)
	}

	// Compute relative path from manifest directory
	relPath, err := filepath.Rel(manifestDir, fullPath)
	if err != nil {
		return nil, fmt.Errorf("relative path: %w", err)
	}

	return &templates.Template{
		Path:        relPath,
		Frontmatter: directives,
		Content:     remaining,
	}, nil
}
