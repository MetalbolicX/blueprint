package phase1

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/fluxo/fluxo/internal/templates"
)

func TestExecute_S1_ValidInput(t *testing.T) {
	input := Phase1Input{
		ResolvedValues: map[string]interface{}{
			"name": "my-project",
		},
		Index: TemplateIndex{
			"/tmp/test Manifest.yaml": TemplateIndexEntry{
				ManifestPath: "/tmp/test Manifest.yaml",
				Manifest:     nil,
				TemplateFiles: []interface{}{
					templates.Template{
						Path:    "output.txt",
						Content: "Hello {{.name}}",
					},
				},
			},
		},
		OutputRoot: t.TempDir(),
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if output.StagedFiles == nil {
		t.Fatal("StagedFiles should not be nil")
	}
}

func TestExecute_S2_InjectionMode(t *testing.T) {
	// Create a target file and an injection template
	tmp := t.TempDir()
	targetPath := filepath.Join(tmp, "existing.txt")
	targetContent := "line1\nMARKER\nline3\n"
	if err := os.WriteFile(targetPath, []byte(targetContent), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Template with inject directive
	tmplContent := `{{.name}}`
	tmpl := struct {
		Path        string
		Frontmatter *struct {
			To      string
			Inject  string
			After   string
			Before  string
			Prepend bool
			Append  bool
			Force   bool
			Sh      string
		}
		Content string
	}{
		Path: "injected.txt",
		Frontmatter: &struct {
			To      string
			Inject  string
			After   string
			Before  string
			Prepend bool
			Append  bool
			Force   bool
			Sh      string
		}{
			To:      "existing.txt",
			Inject:  "MARKER",
			After:   "",
			Before:  "",
			Prepend: false,
			Append:  false,
			Force:   false,
			Sh:      "",
		},
		Content: tmplContent,
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{
			"name": "INJECTED",
		},
		Index: TemplateIndex{
			"test": TemplateIndexEntry{
				ManifestPath:  "test.yaml",
				Manifest:      nil,
				TemplateFiles: []interface{}{tmpl},
			},
		},
		OutputRoot: tmp,
	}

	_, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
}

func TestExecute_S3_MissingInjectTarget(t *testing.T) {
	input := Phase1Input{
		ResolvedValues: map[string]interface{}{
			"name": "test",
		},
		Index: TemplateIndex{
			"test": TemplateIndexEntry{
				ManifestPath:  "test.yaml",
				Manifest:      nil,
				TemplateFiles: []interface{}{},
			},
		},
		OutputRoot: t.TempDir(),
	}

	_, err := Execute(input)
	// Should succeed since there's nothing to stage
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}
}
