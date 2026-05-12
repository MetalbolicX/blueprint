package hooks

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestExecuteHooks_S1_NodeScriptStdoutCaptured(t *testing.T) {
	// Create a temp JS script
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "test.js")
	scriptContent := `console.log("hello from node");`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	config := HookConfig{
		PreGenerate: "node " + scriptPath,
		Timeout:     5 * time.Second,
	}

	err := ExecuteHooks(config, "pre_generate")
	if err != nil {
		t.Fatalf("ExecuteHooks returned error: %v", err)
	}
}

func TestExecuteHooks_S2_ScriptExitsNonZero(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "fail.sh")
	scriptContent := `#!/bin/bash
echo "error occurred" >&2
exit 1
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	config := HookConfig{
		PreGenerate: "bash " + scriptPath,
		Timeout:     5 * time.Second,
	}

	err := ExecuteHooks(config, "pre_generate")
	if err == nil {
		t.Fatal("expected error for non-zero exit, got nil")
	}
}

func TestExecuteHooks_S3_NoHooksConfigured(t *testing.T) {
	config := HookConfig{
		PreGenerate:  "",
		PostGenerate: "",
		Timeout:      5 * time.Second,
	}

	err := ExecuteHooks(config, "pre_generate")
	if err != nil {
		t.Fatalf("ExecuteHooks returned error for empty hooks: %v", err)
	}

	err = ExecuteHooks(config, "post_generate")
	if err != nil {
		t.Fatalf("ExecuteHooks returned error for empty hooks: %v", err)
	}
}

func TestExecuteHooks_UnknownPhase(t *testing.T) {
	config := HookConfig{
		PreGenerate: "node script.js",
		Timeout:     5 * time.Second,
	}

	err := ExecuteHooks(config, "invalid_phase")
	if err == nil {
		t.Fatal("expected error for unknown phase, got nil")
	}
}

func TestExecuteHooks_UnsupportedInterpreter(t *testing.T) {
	config := HookConfig{
		PreGenerate: "ruby script.rb",
		Timeout:     5 * time.Second,
	}

	err := ExecuteHooks(config, "pre_generate")
	if err == nil {
		t.Fatal("expected error for unsupported interpreter, got nil")
	}
}

func TestExecuteHooks_PostGenerate(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "post.js")
	scriptContent := `console.log("post generate ran");`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	config := HookConfig{
		PostGenerate: "node " + scriptPath,
		Timeout:      5 * time.Second,
	}

	err := ExecuteHooks(config, "post_generate")
	if err != nil {
		t.Fatalf("ExecuteHooks returned error: %v", err)
	}
}
