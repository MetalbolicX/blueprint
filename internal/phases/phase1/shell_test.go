package phase1

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestExecuteShellCommand_S1_BashSuccess(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "test.sh")
	scriptContent := `#!/bin/bash
echo "hello from bash"
echo "stdout output" >&1
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := ExecuteShellCommand("bash "+scriptPath, tmp)
	if err != nil {
		t.Fatalf("ExecuteShellCommand returned error: %v", err)
	}
}

func TestExecuteShellCommand_S2_ExitNonZero(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "fail.sh")
	scriptContent := `#!/bin/bash
echo "error occurred" >&2
exit 1
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := ExecuteShellCommand("bash "+scriptPath, tmp)
	if err == nil {
		t.Fatal("expected error for non-zero exit, got nil")
	}
}

func TestExecuteShellCommand_S3_EmptyCommand(t *testing.T) {
	err := ExecuteShellCommand("", t.TempDir())
	if err != nil {
		t.Fatalf("ExecuteShellCommand returned error for empty command: %v", err)
	}
}

func TestExecuteShellCommand_S4_UnsupportedInterpreter(t *testing.T) {
	err := ExecuteShellCommand("ruby script.rb", t.TempDir())
	if err == nil {
		t.Fatal("expected error for unsupported interpreter, got nil")
	}
}

func TestExecuteShellCommand_S5_NodeScript(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "test.js")
	scriptContent := `console.log("hello from node");`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := ExecuteShellCommand("node "+scriptPath, tmp)
	if err != nil {
		t.Fatalf("ExecuteShellCommand returned error: %v", err)
	}
}

func TestExecuteShellCommand_S6_Python3Script(t *testing.T) {
	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "test.py")
	scriptContent := `print("hello from python3")`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := ExecuteShellCommand("python3 "+scriptPath, tmp)
	if err != nil {
		t.Fatalf("ExecuteShellCommand returned error: %v", err)
	}
}

func TestExecuteShellCommand_S7_PwshScript(t *testing.T) {
	// Skip if pwsh not available
	if _, err := exec.LookPath("pwsh"); err != nil {
		t.Skip("pwsh not installed")
	}

	tmp := t.TempDir()
	scriptPath := filepath.Join(tmp, "test.ps1")
	scriptContent := `Write-Host "hello from pwsh"`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := ExecuteShellCommand("pwsh "+scriptPath, tmp)
	if err != nil {
		t.Fatalf("ExecuteShellCommand returned error: %v", err)
	}
}

func TestDetectInterpreter(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"node", "node"},
		{"nodejs", "node"},
		{"python3", "python3"},
		{"bash", "bash"},
		{"sh", "bash"},
		{"pwsh", "pwsh"},
		{"powershell", "pwsh"},
		{"ruby", ""},
		{"python", ""},
		{"go", ""},
	}

	for _, tt := range tests {
		result := detectInterpreter(tt.input)
		if result != tt.expected {
			t.Errorf("detectInterpreter(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}