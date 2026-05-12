package main

import (
	"bytes"
	"flag"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/fluxo/fluxo/internal/engine"
)

func TestLoadHookConfig_WithConfigFile(t *testing.T) {
	tmp := t.TempDir()

	configContent := `hooks:
  pre_generate: "echo pre"
  post_generate: "echo post"
  timeout: 10s
`
	configPath := filepath.Join(tmp, ".fluxo.yaml")
	if err := os.WriteFile(configPath, []byte(configContent), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	hooks, err := loadHookConfig(tmp)
	if err != nil {
		t.Fatalf("loadHookConfig failed: %v", err)
	}

	if hooks.PreGenerate != "echo pre" {
		t.Errorf("expected pre_generate 'echo pre', got %q", hooks.PreGenerate)
	}
	if hooks.PostGenerate != "echo post" {
		t.Errorf("expected post_generate 'echo post', got %q", hooks.PostGenerate)
	}
	if hooks.Timeout != 10*time.Second {
		t.Errorf("expected timeout 10s, got %v", hooks.Timeout)
	}
}

func TestLoadHookConfig_NoConfigFile(t *testing.T) {
	tmp := t.TempDir()

	hooks, err := loadHookConfig(tmp)
	if err != nil {
		t.Fatalf("loadHookConfig failed unexpectedly: %v", err)
	}

	// Should return empty config with default timeout
	if hooks.PreGenerate != "" {
		t.Errorf("expected empty pre_generate, got %q", hooks.PreGenerate)
	}
	if hooks.PostGenerate != "" {
		t.Errorf("expected empty post_generate, got %q", hooks.PostGenerate)
	}
	if hooks.Timeout != 5*time.Second {
		t.Errorf("expected default timeout 5s, got %v", hooks.Timeout)
	}
}

func TestLoadHookConfig_InvalidYAML(t *testing.T) {
	tmp := t.TempDir()

	configPath := filepath.Join(tmp, ".fluxo.yaml")
	if err := os.WriteFile(configPath, []byte("invalid: [yaml"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	_, err := loadHookConfig(tmp)
	if err == nil {
		t.Fatal("expected error for invalid YAML, got nil")
	}
}

func TestScaffoldConfig_CreatesFile(t *testing.T) {
	tmp := t.TempDir()

	err := scaffoldConfig(tmp)
	if err != nil {
		t.Fatalf("scaffoldConfig failed: %v", err)
	}

	configPath := filepath.Join(tmp, ".fluxo.yaml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		t.Fatalf("failed to read scaffolded file: %v", err)
	}

	if !bytes.Contains(data, []byte("Fluxo configuration")) {
		t.Errorf("expected scaffolded file to contain header, got: %s", string(data))
	}
	if !bytes.Contains(data, []byte("generators: []")) {
		t.Errorf("expected scaffolded file to contain 'generators: []', got: %s", string(data))
	}
}

func TestScaffoldConfig_OverwriteFails(t *testing.T) {
	tmp := t.TempDir()

	// Create existing file
	if err := os.WriteFile(filepath.Join(tmp, ".fluxo.yaml"), []byte("existing"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := scaffoldConfig(tmp)
	if err == nil {
		t.Fatal("expected error when file exists, got nil")
	}
}

func TestFindManifest_FoundInTemplatesDir(t *testing.T) {
	tmp := t.TempDir()

	// Create template directory structure
	templateDir := filepath.Join(tmp, "templates", "mytemplate")
	if err := os.MkdirAll(templateDir, 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}
	manifestPath := filepath.Join(templateDir, "manifest.yaml")
	if err := os.WriteFile(manifestPath, []byte("name: test"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	oldwd, _ := os.Getwd()
	defer os.Chdir(oldwd)
	os.Chdir(tmp)

	found, err := findManifest("mytemplate")
	if err != nil {
		t.Fatalf("findManifest failed: %v", err)
	}
	if found != filepath.Join(tmp, "templates", "mytemplate", "manifest.yaml") {
		t.Errorf("expected manifest path, got: %s", found)
	}
}

func TestFindManifest_FoundInGeneratorsDir(t *testing.T) {
	tmp := t.TempDir()

	// Create generators directory structure
	genDir := filepath.Join(tmp, "generators", "mygen")
	if err := os.MkdirAll(genDir, 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}
	manifestPath := filepath.Join(genDir, "manifest.yaml")
	if err := os.WriteFile(manifestPath, []byte("name: test"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	oldwd, _ := os.Getwd()
	defer os.Chdir(oldwd)
	os.Chdir(tmp)

	found, err := findManifest("mygen")
	if err != nil {
		t.Fatalf("findManifest failed: %v", err)
	}
	if found != filepath.Join(tmp, "generators", "mygen", "manifest.yaml") {
		t.Errorf("expected manifest path, got: %s", found)
	}
}

func TestFindManifest_NotFound(t *testing.T) {
	tmp := t.TempDir()

	oldwd, _ := os.Getwd()
	defer os.Chdir(oldwd)
	os.Chdir(tmp)

	_, err := findManifest("nonexistent")
	if err == nil {
		t.Fatal("expected error for non-existent manifest, got nil")
	}
}

func TestFlagParsing_NameFlag(t *testing.T) {
	fs := flag.NewFlagSet("fluxo", flag.ContinueOnError)
	name := fs.String("name", "", "component name")
	force := fs.Bool("force", false, "force overwrite")
	output := fs.String("output", "generated", "output root directory")

	err := fs.Parse([]string{"--name", "mycomponent", "--force", "--output", "/tmp/out"})
	if err != nil {
		t.Fatalf("flag parsing failed: %v", err)
	}

	if *name != "mycomponent" {
		t.Errorf("expected name 'mycomponent', got %q", *name)
	}
	if !*force {
		t.Error("expected force to be true")
	}
	if *output != "/tmp/out" {
		t.Errorf("expected output '/tmp/out', got %q", *output)
	}
}

func TestFlagParsing_ForceFlag(t *testing.T) {
	fs := flag.NewFlagSet("fluxo", flag.ContinueOnError)
	force := fs.Bool("force", false, "force overwrite")

	err := fs.Parse([]string{"--force"})
	if err != nil {
		t.Fatalf("flag parsing failed: %v", err)
	}

	if !*force {
		t.Error("expected force to be true")
	}
}

func TestFlagParsing_OutputFlag(t *testing.T) {
	fs := flag.NewFlagSet("fluxo", flag.ContinueOnError)
	output := fs.String("output", "generated", "output directory")

	err := fs.Parse([]string{"--output", "/custom/output"})
	if err != nil {
		t.Fatalf("flag parsing failed: %v", err)
	}

	if *output != "/custom/output" {
		t.Errorf("expected output '/custom/output', got %q", *output)
	}
}

func TestFlagParsing_HelpFlag(t *testing.T) {
	fs := flag.NewFlagSet("fluxo", flag.ContinueOnError)
	help := fs.Bool("help", false, "show help")

	err := fs.Parse([]string{"--help"})
	if err != nil {
		t.Fatalf("flag parsing failed: %v", err)
	}

	if !*help {
		t.Error("expected help to be true")
	}
}

func TestEngine_HookConfigType(t *testing.T) {
	// Verify HookConfig from engine package is compatible
	cfg := engine.HookConfig{
		PreGenerate:  "echo pre",
		PostGenerate: "echo post",
		Timeout:      5 * time.Second,
	}

	if cfg.PreGenerate != "echo pre" {
		t.Errorf("expected 'echo pre', got %q", cfg.PreGenerate)
	}
}
