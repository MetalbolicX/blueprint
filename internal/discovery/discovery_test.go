package discovery

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiscover_S1_SingleManifestAtRoot(t *testing.T) {
	// Setup: create temp dir with one manifest.yaml at root
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

	if len(index) != 1 {
		t.Fatalf("expected 1 index entry, got %d", len(index))
	}

	// Find the entry
	var entry TemplateIndexEntry
	for _, e := range index {
		entry = e
		break
	}

	if entry.ManifestPath == "" {
		t.Error("ManifestPath should be non-empty")
	}
	if entry.Manifest == nil {
		t.Error("Manifest should be parsed")
	}
	if entry.Manifest.Classification != "web" {
		t.Errorf("expected classification 'web', got %q", entry.Manifest.Classification)
	}
}

func TestDiscover_S2_TwoManifestsNested(t *testing.T) {
	// Setup: two manifests in nested dirs
	tmp := t.TempDir()
	manifestYAML1 := `
name: template-a
classification: web
prompts: []
`
	manifestYAML2 := `
name: template-b
classification: api
prompts: []
`
	subDir := filepath.Join(tmp, "templates", "web")
	if err := os.MkdirAll(subDir, 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(tmp, "manifest.yaml"), []byte(manifestYAML1), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(subDir, "manifest.yaml"), []byte(manifestYAML2), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	index, err := Discover(tmp)
	if err != nil {
		t.Fatalf("Discover returned error: %v", err)
	}

	if len(index) != 2 {
		t.Fatalf("expected 2 index entries, got %d", len(index))
	}
}

func TestFindByClassification_S3_FilterByClassification(t *testing.T) {
	tmp := t.TempDir()
	manifestWeb := `
name: web-tmpl
classification: web
prompts: []
`
	manifestAPI := `
name: api-tmpl
classification: api
prompts: []
`
	if err := os.WriteFile(filepath.Join(tmp, "manifest.yaml"), []byte(manifestWeb), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}
	if err := os.WriteFile(filepath.Join(tmp, "manifest2.yaml"), []byte(manifestAPI), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	index, err := Discover(tmp)
	if err != nil {
		t.Fatalf("Discover returned error: %v", err)
	}

	results := FindByClassification(index, "web")
	if len(results) != 1 {
		t.Fatalf("expected 1 result for 'web', got %d", len(results))
	}

	if results[0].Manifest.Name != "web-tmpl" {
		t.Errorf("expected name 'web-tmpl', got %q", results[0].Manifest.Name)
	}
}

func TestDiscover_ManifestParseError(t *testing.T) {
	tmp := t.TempDir()
	invalidYAML := `
name: test
classification: web
prompts:
  - name: ""
`
	if err := os.WriteFile(filepath.Join(tmp, "manifest.yaml"), []byte(invalidYAML), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	_, err := Discover(tmp)
	if err == nil {
		t.Error("expected error for invalid manifest, got nil")
	}
}

func TestDiscover_NoManifests(t *testing.T) {
	tmp := t.TempDir()
	// Write a non-manifest file
	if err := os.WriteFile(filepath.Join(tmp, "readme.md"), []byte("# Hello"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	index, err := Discover(tmp)
	if err != nil {
		t.Fatalf("Discover returned error: %v", err)
	}

	if len(index) != 0 {
		t.Fatalf("expected 0 index entries, got %d", len(index))
	}
}
