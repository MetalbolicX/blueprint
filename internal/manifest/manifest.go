// Package manifest parses and validates manifest.yaml files.
package manifest

import (
	"fmt"
	"strings"

	"gopkg.in/yaml.v3"
)

// Manifest represents the parsed contents of a manifest.yaml file.
type Manifest struct {
	Name           string
	Classification string
	Metadata       map[string]interface{}
	Prompts        []Prompt
}

// Prompt represents a single prompt defined in a manifest.
type Prompt struct {
	Name        string
	Type        string // "input", "select", "confirm"
	Description string
	Default     interface{}
	Options     []string
}

// Parse reads YAML bytes and returns a Manifest, or an error if the YAML
// is invalid or fails validation.
func Parse(yamlBytes []byte) (*Manifest, error) {
	var m Manifest
	if err := yaml.Unmarshal(yamlBytes, &m); err != nil {
		return nil, fmt.Errorf("parse error: %w", err)
	}

	// Validation: classification non-empty
	if strings.TrimSpace(m.Classification) == "" {
		return nil, fmt.Errorf("classification required")
	}

	// Validation: each prompt has a non-empty name
	for i, p := range m.Prompts {
		if strings.TrimSpace(p.Name) == "" {
			return nil, fmt.Errorf("prompt %d: name required", i)
		}
		// Validation: prompt type must be one of the known types
		switch p.Type {
		case "input", "select", "confirm":
			// valid
		case "":
			return nil, fmt.Errorf("prompt %q: type required", p.Name)
		default:
			return nil, fmt.Errorf("prompt %q: invalid type %q (expected input, select, or confirm)", p.Name, p.Type)
		}
	}

	return &m, nil
}
