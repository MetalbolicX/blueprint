package discovery

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/fluxo/fluxo/internal/templates"
)

func TestDiscover_S4_LoadsTemplatesFromFilesSubdir(t *testing.T) {
	// Setup: manifest with templates in files/ subdirectory
	tmp := t.TempDir()
	manifestYAML := `
name: test-template
classification: web
prompts: []
`
	filesDir := filepath.Join(tmp, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	if err := os.WriteFile(filepath.Join(tmp, "manifest.yaml"), []byte(manifestYAML), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Template with frontmatter
	templateWithFM := `---
to: output.txt
---
Hello <%= name %>
`
	if err := os.WriteFile(filepath.Join(filesDir, "greeting.ejs.t"), []byte(templateWithFM), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Template without frontmatter
	templateNoFM := `This is a plain file write.
No frontmatter here.
`
	if err := os.WriteFile(filepath.Join(filesDir, "readme.tmpl"), []byte(templateNoFM), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	index, err := Discover(tmp)
	if err != nil {
		t.Fatalf("Discover returned error: %v", err)
	}

	if len(index) != 1 {
		t.Fatalf("expected 1 index entry, got %d", len(index))
	}

	var entry TemplateIndexEntry
	for _, e := range index {
		entry = e
		break
	}

	if len(entry.TemplateFiles) != 2 {
		t.Fatalf("expected 2 template files, got %d", len(entry.TemplateFiles))
	}

	// Find the template with frontmatter
	var greetingTmpl templates.Template
	var readmeTmpl templates.Template
	for _, tmpl := range entry.TemplateFiles {
		if tmpl.Path == "files/greeting.ejs.t" {
			greetingTmpl = tmpl
		}
		if tmpl.Path == "files/readme.tmpl" {
			readmeTmpl = tmpl
		}
	}

	if greetingTmpl.Path == "" {
		t.Error("greeting.ejs.t not found in TemplateFiles")
	}
	if greetingTmpl.Frontmatter == nil {
		t.Error("greeting.ejs.t Frontmatter should not be nil")
	}
	if greetingTmpl.Frontmatter.To != "output.txt" {
		t.Errorf("expected frontmatter.To 'output.txt', got %q", greetingTmpl.Frontmatter.To)
	}
	if greetingTmpl.Content != "Hello <%= name %>\n" {
		t.Errorf("expected content 'Hello <%%= name %%>\\n', got %q", greetingTmpl.Content)
	}

	if readmeTmpl.Path == "" {
		t.Error("readme.tmpl not found in TemplateFiles")
	}
	// Templates without frontmatter should have empty directives (not nil Frontmatter)
	if readmeTmpl.Frontmatter == nil {
		t.Error("readme.tmpl Frontmatter should not be nil (empty directives)")
	}
	if readmeTmpl.Content != templateNoFM {
		t.Errorf("readme.tmpl content mismatch, got %q", readmeTmpl.Content)
	}
}

func TestDiscover_S5_AllFilesInFilesDirLoaded(t *testing.T) {
	// Setup: manifest with multiple template files
	tmp := t.TempDir()
	manifestYAML := `
name: test-template
classification: web
prompts: []
`
	filesDir := filepath.Join(tmp, "files")
	if err := os.MkdirAll(filesDir, 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	if err := os.WriteFile(filepath.Join(tmp, "manifest.yaml"), []byte(manifestYAML), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Template with .ejs.t extension
	tmpl1 := `---
to: output1.txt
---
Content 1
`
	if err := os.WriteFile(filepath.Join(filesDir, "tmpl1.ejs.t"), []byte(tmpl1), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Template with .tmpl extension
	tmpl2 := `---
to: output2.txt
---
Content 2
`
	if err := os.WriteFile(filepath.Join(filesDir, "tmpl2.tmpl"), []byte(tmpl2), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	index, err := Discover(tmp)
	if err != nil {
		t.Fatalf("Discover returned error: %v", err)
	}

	var entry TemplateIndexEntry
	for _, e := range index {
		entry = e
		break
	}

	if len(entry.TemplateFiles) != 2 {
		t.Fatalf("expected 2 template files, got %d", len(entry.TemplateFiles))
	}
}

func TestDiscover_S6_NoFilesSubdir(t *testing.T) {
	// Setup: manifest without files/ subdirectory
	tmp := t.TempDir()
	manifestYAML := `
name: test-template
classification: web
prompts: []
`
	if err := os.WriteFile(filepath.Join(tmp, "manifest.yaml"), []byte(manifestYAML), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	index, err := Discover(tmp)
	if err != nil {
		t.Fatalf("Discover returned error: %v", err)
	}

	var entry TemplateIndexEntry
	for _, e := range index {
		entry = e
		break
	}

	if len(entry.TemplateFiles) != 0 {
		t.Fatalf("expected 0 template files when no files/ subdir, got %d", len(entry.TemplateFiles))
	}
}