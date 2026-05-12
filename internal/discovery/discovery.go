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

		entry := TemplateIndexEntry{
			ManifestPath:  path,
			Manifest:      m,
			TemplateFiles: nil, // Templates resolved later in phase1
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
