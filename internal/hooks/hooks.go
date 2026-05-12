// Package hooks executes pre/post generate scripts.
package hooks

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// HookConfig holds the hook scripts and execution parameters.
type HookConfig struct {
	PreGenerate  string
	PostGenerate string
	Timeout      time.Duration
}

// ExecuteHooks runs either pre_generate or post_generate hook based on phase.
// It detects the interpreter from the command (node, python3, bash, powershell).
func ExecuteHooks(config HookConfig, phase string) error {
	var cmdStr string
	switch phase {
	case "pre_generate":
		cmdStr = config.PreGenerate
	case "post_generate":
		cmdStr = config.PostGenerate
	default:
		return fmt.Errorf("unknown phase: %q (expected pre_generate or post_generate)", phase)
	}

	if cmdStr == "" {
		return nil
	}

	ctx, cancel := context.WithTimeout(context.Background(), config.Timeout)
	defer cancel()

	if err := runScript(ctx, cmdStr); err != nil {
		return err
	}

	return nil
}

// runScript detects interpreter and executes the script.
func runScript(ctx context.Context, cmdStr string) error {
	parts := strings.Fields(cmdStr)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	interpreter := detectInterpreter(parts[0])
	if interpreter == "" {
		return fmt.Errorf("unsupported interpreter: %q", parts[0])
	}

	var cmd *exec.Cmd
	if len(parts) == 1 {
		cmd = exec.CommandContext(ctx, interpreter)
	} else {
		cmd = exec.CommandContext(ctx, interpreter, parts[1:]...)
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("hook failed: %w (stderr: %s)", err, stderr.String())
	}

	return nil
}

// detectInterpreter returns the canonical interpreter name.
func detectInterpreter(cmd string) string {
	switch cmd {
	case "node", "nodejs":
		return "node"
	case "python3":
		return "python3"
	case "bash", "sh":
		return "bash"
	case "pwsh", "powershell":
		return "pwsh"
	default:
		return ""
	}
}
