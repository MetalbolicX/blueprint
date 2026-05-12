package phase2

import (
	"os"
	"path/filepath"
	"testing"
)

func TestExecute_S1_Phase2Succeeds(t *testing.T) {
	// Setup: create a temp staging dir with one file
	stagingDir := t.TempDir()
	outputRoot := t.TempDir()

	stagedPath := filepath.Join(stagingDir, "testfile.txt")
	stagedContent := "hello world"
	if err := os.WriteFile(stagedPath, []byte(stagedContent), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	input := Phase2Input{
		StagedFiles: map[string]string{
			"testfile.txt": stagedPath,
		},
		OutputRoot: outputRoot,
	}

	output, err := Execute(input)
	if err != nil {
		t.Fatalf("Execute returned error: %v", err)
	}

	if len(output.CommittedFiles) != 1 {
		t.Fatalf("expected 1 committed file, got %d", len(output.CommittedFiles))
	}

	// Verify file was committed
	committedPath := filepath.Join(outputRoot, "testfile.txt")
	data, err := os.ReadFile(committedPath)
	if err != nil {
		t.Fatalf("could not read committed file: %v", err)
	}

	if string(data) != stagedContent {
		t.Errorf("expected %q, got %q", stagedContent, string(data))
	}

	// Verify staging dir was deleted
	if _, err := os.Stat(stagingDir); !os.IsNotExist(err) {
		t.Errorf("staging dir should be deleted")
	}
}

func TestExecute_S2_Phase2FailsMidCommit(t *testing.T) {
	// Setup: create staging dir with one valid file and one that will fail
	stagingDir := t.TempDir()
	outputRoot := t.TempDir()

	validPath := filepath.Join(stagingDir, "valid.txt")
	if err := os.WriteFile(validPath, []byte("valid content"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Make output root read-only to cause failure
	if err := os.Chmod(outputRoot, 0000); err != nil {
		t.Fatalf("setup error: %v", err)
	}
	defer os.Chmod(outputRoot, 0755) // restore for cleanup

	input := Phase2Input{
		StagedFiles: map[string]string{
			"valid.txt":         validPath,
			"readonly/fail.txt": filepath.Join(stagingDir, "readonly", "fail.txt"),
		},
		OutputRoot: outputRoot,
	}

	_, err := Execute(input)
	if err == nil {
		t.Fatal("expected error for read-only output, got nil")
	}
}

func TestExecute_S3_CommitToNonExistentRoot(t *testing.T) {
	// Use a path that definitely doesn't exist and can't be created
	stagingDir := t.TempDir()
	stagedPath := filepath.Join(stagingDir, "test.txt")
	if err := os.WriteFile(stagedPath, []byte("content"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	// Use /nonexistent as output root (should fail)
	input := Phase2Input{
		StagedFiles: map[string]string{
			"test.txt": stagedPath,
		},
		OutputRoot: "/nonexistent/fluxo-test-output",
	}

	_, err := Execute(input)
	if err == nil {
		t.Fatal("expected error for non-existent root, got nil")
	}
}

func TestRollback_S4(t *testing.T) {
	stagingDir := t.TempDir()
	stagedPath := filepath.Join(stagingDir, "test.txt")
	if err := os.WriteFile(stagedPath, []byte("content"), 0644); err != nil {
		t.Fatalf("setup error: %v", err)
	}

	err := Rollback(map[string]string{"test.txt": stagedPath})
	if err != nil {
		t.Fatalf("Rollback returned error: %v", err)
	}

	// Verify staging dir was deleted
	if _, err := os.Stat(stagingDir); !os.IsNotExist(err) {
		t.Errorf("staging dir should be deleted after rollback")
	}
}

func TestRollback_EmptyFiles(t *testing.T) {
	err := Rollback(map[string]string{})
	if err != nil {
		t.Fatalf("Rollback returned error for empty files: %v", err)
	}
}
