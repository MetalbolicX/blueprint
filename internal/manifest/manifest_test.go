package manifest

import (
	"testing"
)

func TestParse_S1_ValidYAML(t *testing.T) {
	yamlBytes := []byte(`
name: my-template
classification: web
metadata:
  description: A test template
prompts:
  - name: user
    type: input
    description: "Username"
    default: admin
`)
	m, err := Parse(yamlBytes)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if m == nil {
		t.Fatal("expected non-nil Manifest")
	}
	if m.Name != "my-template" {
		t.Errorf("expected name %q, got %q", "my-template", m.Name)
	}
	if m.Classification != "web" {
		t.Errorf("expected classification %q, got %q", "web", m.Classification)
	}
	if len(m.Prompts) != 1 {
		t.Fatalf("expected 1 prompt, got %d", len(m.Prompts))
	}
	if m.Prompts[0].Name != "user" {
		t.Errorf("expected prompt name %q, got %q", "user", m.Prompts[0].Name)
	}
	if m.Prompts[0].Type != "input" {
		t.Errorf("expected prompt type %q, got %q", "input", m.Prompts[0].Type)
	}
}

func TestParse_S2_MissingPromptName(t *testing.T) {
	yamlBytes := []byte(`
name: my-template
classification: web
prompts:
  - name: ""
    type: input
    description: "Username"
`)
	_, err := Parse(yamlBytes)
	if err == nil {
		t.Fatal("expected non-nil error for missing prompt name")
	}
	// Should mention "name required"
	if err.Error() == "" {
		t.Fatal("error message should not be empty")
	}
}

func TestParse_S3_InvalidYAML(t *testing.T) {
	yamlBytes := []byte(`
name: my-template
classification: [unclosed
`)
	_, err := Parse(yamlBytes)
	if err == nil {
		t.Fatal("expected non-nil error for invalid YAML")
	}
	// Should wrap parse error with context
	if err.Error() == "" {
		t.Fatal("error message should not be empty")
	}
}
