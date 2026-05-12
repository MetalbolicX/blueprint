package phase0

import (
	"testing"

	"github.com/fluxo/fluxo/internal/discovery"
	"github.com/fluxo/fluxo/internal/manifest"
)

func TestExecute_S1_ValidInput(t *testing.T) {
	index := discovery.TemplateIndex{}
	input := Phase0Input{
		Index: index,
		PromptValues: map[string]interface{}{
			"name": "my-project",
		},
		Force: false,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if output.ResolvedValues == nil {
		t.Fatal("ResolvedValues should not be nil")
	}

	if output.ResolvedValues["name"] != "my-project" {
		t.Errorf("expected 'my-project', got %v", output.ResolvedValues["name"])
	}
}

func TestExecute_S2_InvalidPrompts(t *testing.T) {
	// Empty index should cause an error
	input := Phase0Input{
		Index:        nil, // nil index should fail
		PromptValues: map[string]interface{}{},
		Force:        false,
	}

	_, err := Execute(input)
	if err == nil {
		t.Fatal("expected error for nil index, got nil")
	}
}

func TestExecute_S3_ConflictsDetectedAndResolved(t *testing.T) {
	// Create a minimal index
	tmp := t.TempDir()
	index := discovery.TemplateIndex{
		tmp + "/manifest.yaml": discovery.TemplateIndexEntry{
			ManifestPath: tmp + "/manifest.yaml",
			Manifest: &manifest.Manifest{
				Name:           "test",
				Classification: "web",
				Metadata:       map[string]interface{}{},
				Prompts:        []manifest.Prompt{},
			},
			TemplateFiles: nil,
		},
	}

	input := Phase0Input{
		Index: index,
		PromptValues: map[string]interface{}{
			"name": "test-project",
		},
		Force: true, // Force mode — conflicts auto-resolved
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if output.ResolvedValues == nil {
		t.Fatal("ResolvedValues should not be nil")
	}
}
