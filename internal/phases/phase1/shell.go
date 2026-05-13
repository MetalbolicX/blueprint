package phase1

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

// ExecuteShellCommand runs a shell command and returns an error on non-zero exit.
// It captures stdout/stderr and logs them. Commands run in the specified cwd.
func ExecuteShellCommand(command string, cwd string) error {
	if command == "" {
		return nil
	}

	parts := strings.Fields(command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command")
	}

	interpreter := detectInterpreter(parts[0])
	if interpreter == "" {
		return fmt.Errorf("unsupported interpreter: %q", parts[0])
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	var cmd *exec.Cmd
	if len(parts) == 1 {
		cmd = exec.CommandContext(ctx, interpreter)
	} else {
		cmd = exec.CommandContext(ctx, interpreter, parts[1:]...)
	}

	if cwd != "" {
		cmd.Dir = cwd
	}

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	if err != nil {
		return fmt.Errorf("shell command failed (exit %d): %s (stderr: %s)",
			cmd.ProcessState.ExitCode(), stdout.String(), stderr.String())
	}

	return nil
}

// detectInterpreter returns the canonical interpreter name.
// Mirrors hooks.detectInterpreter for consistency.
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