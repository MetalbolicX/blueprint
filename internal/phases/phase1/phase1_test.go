package phase1

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/fluxo/fluxo/internal/templates"
)

func TestExecute_InjectionOperations(t *testing.T) {
	// Create a temp project dir with existing files to inject into
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	// Create existing target file
	existingFile := filepath.Join(projectDir, "existing.go")
	existingContent := `package main

type Config struct {
	Name string
}
`
	if err := os.WriteFile(existingFile, []byte(existingContent), 0644); err != nil {
		t.Fatal(err)
	}

	// Create template with inject frontmatter
	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:     "existing.go",
			Inject: "type Config struct",
		},
		Content: `
// Injected section
type Middle struct{}
`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	// Verify staged file has injection applied
	stagedPath, ok := output.StagedFiles["inject.txt"]
	if !ok {
		t.Fatal("expected staged file for inject.txt")
	}

	stagedContent, err := os.ReadFile(stagedPath)
	if err != nil {
		t.Fatal(err)
	}

	result := string(stagedContent)

	// For replace mode: pattern "type Config struct" is replaced by content
	// So "type Config struct {" becomes "// Injected section\ntype Middle struct{}\n"
	// Result should contain injected content
	if !strings.Contains(result, "type Middle struct{}") {
		t.Errorf("expected injected content, got: %s", result)
	}
}

func TestExecute_InjectionAfter(t *testing.T) {
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	existingFile := filepath.Join(projectDir, "target.txt")
	existingContent := `line1
line2
line3
`
	if err := os.WriteFile(existingFile, []byte(existingContent), 0644); err != nil {
		t.Fatal(err)
	}

	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:    "target.txt",
			After: "line2",
		},
		Content: `inserted after line2
`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	stagedPath, ok := output.StagedFiles["inject.txt"]
	if !ok {
		t.Fatal("expected staged file")
	}

	stagedContent, _ := os.ReadFile(stagedPath)
	result := string(stagedContent)

	// After mode: pattern is replaced with pattern + content
	// With pattern "line2" and content "inserted after line2\n"
	// The "line2" at end of file becomes "line2inserted after line2\n"
	// Final: line1\nline2inserted after line2\nline3\n
	// Check all three parts are present
	if strings.Contains(result, "line1") && strings.Contains(result, "line3") {
		// line2 was replaced with line2+content, so we look for the combined string
		if strings.Contains(result, "line2inserted after line2") {
			// success
		} else if strings.Contains(result, "line2\ninserted") {
			// success - newline was preserved
		} else {
			t.Errorf("unexpected injection result: %q", result)
		}
	} else {
		t.Errorf("expected 'line1' and 'line3' in result: %q", result)
	}
}

func TestExecute_InjectionBefore(t *testing.T) {
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	existingFile := filepath.Join(projectDir, "target.txt")
	existingContent := `line1
line2
line3
`
	if err := os.WriteFile(existingFile, []byte(existingContent), 0644); err != nil {
		t.Fatal(err)
	}

	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:     "target.txt",
			Before: "line3",
		},
		Content: `before line3
`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	stagedPath, ok := output.StagedFiles["inject.txt"]
	if !ok {
		t.Fatal("expected staged file")
	}

	stagedContent, _ := os.ReadFile(stagedPath)
	result := string(stagedContent)

	// For 'before' mode: pattern is replaced with content + "$0"
	// So "line3" becomes "before line3\nline3"
	if !strings.Contains(result, "before line3") || !strings.Contains(result, "line3") {
		t.Errorf("unexpected injection result: %s", result)
	}
}

func TestExecute_InjectionPrepend(t *testing.T) {
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	existingFile := filepath.Join(projectDir, "target.txt")
	existingContent := `line1
line2
`
	if err := os.WriteFile(existingFile, []byte(existingContent), 0644); err != nil {
		t.Fatal(err)
	}

	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:      "target.txt",
			Prepend: true,
		},
		Content: `prepended content
`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	stagedPath, ok := output.StagedFiles["inject.txt"]
	if !ok {
		t.Fatal("expected staged file")
	}

	stagedContent, _ := os.ReadFile(stagedPath)
	result := string(stagedContent)

	// Should have prepended content before original
	if !strings.Contains(result, "prepended content\nline1") {
		t.Errorf("expected 'prepended content\\nline1', got: %s", result)
	}
}

func TestExecute_InjectionAppend(t *testing.T) {
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	existingFile := filepath.Join(projectDir, "target.txt")
	existingContent := `line1
line2
`
	if err := os.WriteFile(existingFile, []byte(existingContent), 0644); err != nil {
		t.Fatal(err)
	}

	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:     "target.txt",
			Append: true,
		},
		Content: `
appended content
`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	stagedPath, ok := output.StagedFiles["inject.txt"]
	if !ok {
		t.Fatal("expected staged file")
	}

	stagedContent, _ := os.ReadFile(stagedPath)
	result := string(stagedContent)

	// Should have appended content at end
	if !strings.HasSuffix(result, "appended content\n") {
		t.Errorf("expected content to end with 'appended content\\n', got: %s", result)
	}
}

func TestExecute_InjectionFileNotFound(t *testing.T) {
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	// Template targets non-existent file
	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:     "nonexistent.txt",
			Inject: "pattern",
		},
		Content: `injected content`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	_, err = Execute(input)
	if err == nil {
		t.Error("expected error when target file doesn't exist")
	}
}

func TestExecute_InjectionWithForceCreatesFile(t *testing.T) {
	projectDir, err := os.MkdirTemp("", "fluxo-test-*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(projectDir)

	// Template with force:true targeting non-existent file
	tmpl := templates.Template{
		Path: "inject.txt",
		Frontmatter: &templates.Directives{
			To:     "newfile.txt",
			Inject: "pattern",
			Force:  true,
		},
		Content: `new content`,
	}

	index := TemplateIndex{
		"manifest": {
			ManifestPath:  "manifest.yaml",
			Manifest:      nil,
			TemplateFiles: []interface{}{tmpl},
		},
	}

	input := Phase1Input{
		ResolvedValues: map[string]interface{}{},
		Index:          index,
		OutputRoot:     projectDir,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute failed: %v", err)
	}

	stagedPath, ok := output.StagedFiles["inject.txt"]
	if !ok {
		t.Fatal("expected staged file")
	}

	stagedContent, _ := os.ReadFile(stagedPath)
	result := string(stagedContent)

	// With force:true and no existing file, the file is created with rendered content
	// Result should contain the rendered template
	if !strings.Contains(result, "new content") {
		t.Errorf("expected 'new content' in result, got: %q", result)
	}
}