package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/fluxo/fluxo/internal/engine"
	"gopkg.in/yaml.v3"
)

// HookConfig mirrors internal/hooks.HookConfig for YAML loading.
type HookConfig struct {
	PreGenerate  string
	PostGenerate string
	Timeout      time.Duration
}

// FluxoConfig represents the optional .fluxo.yaml file.
type FluxoConfig struct {
	Generators []GeneratorConfig `yaml:"generators"`
	Hooks      HookConfigYAML    `yaml:"hooks"`
}

// HookConfigYAML is the YAML representation of hook settings.
type HookConfigYAML struct {
	PreGenerate  string `yaml:"pre_generate"`
	PostGenerate string `yaml:"post_generate"`
	Timeout      string `yaml:"timeout"`
}

// GeneratorConfig holds per-generator settings (future use).
type GeneratorConfig struct {
	Name           string `yaml:"name"`
	Classification  string `yaml:"classification"`
	TemplateRoot   string `yaml:"template_root"`
	OutputRoot     string `yaml:"output_root"`
}

// loadHookConfig reads .fluxo.yaml and returns HookConfig.
func loadHookConfig(dir string) (engine.HookConfig, error) {
	configPath := filepath.Join(dir, ".fluxo.yaml")
	data, err := os.ReadFile(configPath)
	if err != nil {
		if os.IsNotExist(err) {
			return engine.HookConfig{Timeout: 5 * time.Second}, nil
		}
		return engine.HookConfig{}, fmt.Errorf("read .fluxo.yaml: %w", err)
	}

	var cfg FluxoConfig
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return engine.HookConfig{}, fmt.Errorf("parse .fluxo.yaml: %w", err)
	}

	timeout := 5 * time.Second
	if cfg.Hooks.Timeout != "" {
		timeout, err = time.ParseDuration(cfg.Hooks.Timeout)
		if err != nil {
			return engine.HookConfig{}, fmt.Errorf("invalid timeout %q: %w", cfg.Hooks.Timeout, err)
		}
	}

	return engine.HookConfig{
		PreGenerate:  cfg.Hooks.PreGenerate,
		PostGenerate: cfg.Hooks.PostGenerate,
		Timeout:      timeout,
	}, nil
}

// scaffoldConfig writes a default .fluxo.yaml to dir.
func scaffoldConfig(dir string) error {
	defaultConfig := `# Fluxo configuration
# This file configures template generators and hooks.

generators: []
hooks:
  pre_generate: ""
  post_generate: ""
  timeout: 5s
`

	configPath := filepath.Join(dir, ".fluxo.yaml")
	if _, err := os.Stat(configPath); err == nil {
		return fmt.Errorf(".fluxo.yaml already exists at %s", configPath)
	}
	if err := os.WriteFile(configPath, []byte(defaultConfig), 0644); err != nil {
		return fmt.Errorf("write .fluxo.yaml: %w", err)
	}

	fmt.Printf("Scaffolded .fluxo.yaml at %s\n", configPath)
	return nil
}

// findManifest looks for the manifest path for a given classification.
func findManifest(classification string) (string, error) {
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("cannot determine working directory: %w", err)
	}

	searchPaths := []string{
		filepath.Join(cwd, "templates", classification, "manifest.yaml"),
		filepath.Join(cwd, "generators", classification, "manifest.yaml"),
		filepath.Join(cwd, "manifests", classification, "manifest.yaml"),
	}

	for _, p := range searchPaths {
		if _, err := os.Stat(p); err == nil {
			return p, nil
		}
	}

	return "", fmt.Errorf("manifest not found for classification %q (searched templates/, generators/, manifests/)", classification)
}

func main() {
	// argv-based: fluxo <generator> <action> [--name NAME] [--force] [--output DIR]
	if len(os.Args) < 2 {
		fmt.Fprintf(os.Stderr, "Usage: fluxo <generator> <action> [--name NAME] [--force] [--output DIR]\n")
		fmt.Fprintf(os.Stderr, "Try 'fluxo --help' for more information.\n")
		os.Exit(1)
		return
	}

	var (
		helpFlag   = flag.Bool("help", false, "show help")
		nameFlag   = flag.String("name", "", "component name")
		forceFlag  = flag.Bool("force", false, "force overwrite / skip prompts")
		outputFlag = flag.String("output", "generated", "output root directory")
	)
	_ = nameFlag   // TODO: wire into engine context or prompt resolution
	_ = forceFlag  // TODO: wire into Phase0 input

	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: fluxo <generator> <action> [--name NAME] [--force] [--output DIR]\n\n")
		fmt.Fprintf(os.Stderr, "Arguments:\n")
		fmt.Fprintf(os.Stderr, "  generator    generator classification (e.g. 'mytemplate')\n")
		fmt.Fprintf(os.Stderr, "  action       action to perform (e.g. 'new')\n\n")
		fmt.Fprintf(os.Stderr, "Flags:\n")
		flag.PrintDefaults()
		fmt.Fprintf(os.Stderr, "\nCommands:\n")
		fmt.Fprintf(os.Stderr, "  init           scaffold a .fluxo.yaml config file\n")
		fmt.Fprintf(os.Stderr, "  generate       run template generation\n")
	}

	flag.Parse()

	if *helpFlag {
		flag.Usage()
		os.Exit(0)
		return
	}

	// Handle built-in commands
	if os.Args[1] == "init" {
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: cannot determine current directory: %v\n", err)
			os.Exit(1)
			return
		}
		if err := scaffoldConfig(cwd); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
			return
		}
		os.Exit(0)
		return
	}

	if os.Args[1] == "generate" {
		if len(os.Args) < 3 {
			fmt.Fprintf(os.Stderr, "Error: 'generate' requires a classification argument\n")
			fmt.Fprintf(os.Stderr, "Usage: fluxo generate <classification> [--name NAME] [--force] [--output DIR]\n")
			os.Exit(1)
			return
		}
		classification := os.Args[2]

		// Find manifest
		manifestPath, err := findManifest(classification)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
			return
		}

		// Set output root
		outputRoot := *outputFlag
		if outputRoot == "" {
			outputRoot = "generated"
		}

		// Load hook config from .fluxo.yaml
		cwd, err := os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: cannot determine current directory: %v\n", err)
			os.Exit(1)
			return
		}

		hookConfig, err := loadHookConfig(cwd)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error loading .fluxo.yaml: %v\n", err)
			os.Exit(1)
			return
		}

		// Initialize engine
		eng := engine.NewEngine(hookConfig)

		// Build context input from CLI flags
		// Note: cwd is already set above for loadHookConfig
		cwdGet, err := os.Getwd()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: cannot determine current directory: %v\n", err)
			os.Exit(1)
			return
		}

		// Parse CLI attributes from remaining args (after flags)
		attrs := engine.ParseCLIAttributes(flag.Args())
		if *nameFlag != "" {
			attrs["name"] = *nameFlag
		}

		contextInput := engine.ContextInput{
			CWD:          cwdGet,
			ManifestPath: manifestPath,
			Name:         *nameFlag,
			Attributes:   attrs,
		}

		// Execute engine
		ctx := context.Background()
		result, err := eng.Execute(ctx, manifestPath, outputRoot, contextInput)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
			return
		}

		// Print summary
		fmt.Printf("Fluxo: generated %d file(s)\n", len(result.CommittedFiles))
		if len(result.CommittedFiles) > 0 {
			fmt.Println("Files:")
			for _, f := range result.CommittedFiles {
				fmt.Printf("  - %s\n", f)
			}
		}
		if len(result.InjectionLog) > 0 {
			fmt.Println("Injections:")
			for _, inj := range result.InjectionLog {
				fmt.Printf("  - %s into %s (%d lines)\n", inj.TemplatePath, inj.DestPath, inj.LinesInjected)
			}
		}

		os.Exit(0)
		return
	}

	// Unknown command
	fmt.Fprintf(os.Stderr, "Error: unknown command %q\n", os.Args[1])
	fmt.Fprintf(os.Stderr, "Usage: fluxo <generator> <action> [--name NAME] [--force] [--output DIR]\n")
	os.Exit(1)
}
