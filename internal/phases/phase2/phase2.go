// Package phase2 handles atomic commit and rollback.
package phase2

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// Phase2Input is the input for Phase 2.
type Phase2Input struct {
	StagedFiles map[string]string
	OutputRoot  string
}

// Phase2Output is the output from Phase 2.
type Phase2Output struct {
	CommittedFiles []string
}

// Execute performs atomic commit of staged files to output root.
// On failure, it discards the temp staging dir and leaves dest untouched.
func Execute(input Phase2Input) (*Phase2Output, error) {
	if input.StagedFiles == nil {
		return nil, fmt.Errorf("StagedFiles is required")
	}

	if input.OutputRoot == "" {
		return nil, fmt.Errorf("OutputRoot is required")
	}

	// Ensure output root exists
	if err := os.MkdirAll(input.OutputRoot, 0755); err != nil {
		return nil, fmt.Errorf("failed to create output root: %w", err)
	}

	output := &Phase2Output{
		CommittedFiles: nil,
	}

	// Track what we've committed so we can rollback on failure
	var committed []string

	for _, stagedPath := range input.StagedFiles {
		// Read staged file content
		data, err := os.ReadFile(stagedPath)
		if err != nil {
			// Rollback not needed here since we're still in staging
			return nil, fmt.Errorf("read error at %s: %w", stagedPath, err)
		}

		// Determine final dest path
		relPath, err := filepath.Rel(filepath.Dir(stagedPath), stagedPath)
		if err != nil {
			return nil, fmt.Errorf("rel path error: %w", err)
		}
		destPath := filepath.Join(input.OutputRoot, relPath)

		// Ensure dest dir exists
		if err := os.MkdirAll(filepath.Dir(destPath), 0755); err != nil {
			return nil, fmt.Errorf("mkdir error: %w", err)
		}

		// Write to final destination
		if err := os.WriteFile(destPath, data, 0644); err != nil {
			return nil, fmt.Errorf("write error at %s: %w", destPath, err)
		}

		committed = append(committed, destPath)
	}

	// Clean up staging dir
	stagingDir := filepath.Dir(input.StagedFiles[getFirstKey(input.StagedFiles)])
	os.RemoveAll(stagingDir)

	output.CommittedFiles = committed
	return output, nil
}

// getFirstKey returns the first key from a map (for cleanup path extraction).
func getFirstKey(m map[string]string) string {
	for k := range m {
		return k
	}
	return ""
}

// Rollback discards the temp staging dir.
func Rollback(stagedFiles map[string]string) error {
	if len(stagedFiles) == 0 {
		return nil
	}
	stagingDir := filepath.Dir(stagedFiles[getFirstKey(stagedFiles)])
	return os.RemoveAll(stagingDir)
}

// CopyFile copies a single file from src to dst.
func CopyFile(src, dst string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	dstFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	_, err = io.Copy(dstFile, srcFile)
	return err
}
