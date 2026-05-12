package conflicts

import (
	"bufio"
	"strings"
	"testing"
)

func TestBulkResolve_S1_NoConflicts(t *testing.T) {
	r := &Resolver{Force: false, Scanner: bufio.NewScanner(strings.NewReader(""))}

	result, err := r.BulkResolve(nil)
	if err != nil {
		t.Fatalf("BulkResolve returned error: %v", err)
	}

	if len(result) != 0 {
		t.Fatalf("expected empty result, got %d entries", len(result))
	}
}

func TestBulkResolve_S2_BulkYes(t *testing.T) {
	conflicts := []Conflict{
		{DestPath: "file1.txt", Source: "tmpl1"},
		{DestPath: "file2.txt", Source: "tmpl2"},
		{DestPath: "file3.txt", Source: "tmpl3"},
	}

	r := &Resolver{Force: false, Scanner: bufio.NewScanner(strings.NewReader("y\n"))}

	result, err := r.BulkResolve(conflicts)
	if err != nil {
		t.Fatalf("BulkResolve returned error: %v", err)
	}

	for _, c := range conflicts {
		if !result[c.DestPath] {
			t.Errorf("expected true for %s", c.DestPath)
		}
	}
}

func TestBulkResolve_S3_ForceAllOverwritten(t *testing.T) {
	conflicts := []Conflict{
		{DestPath: "file1.txt", Source: "tmpl1"},
		{DestPath: "file2.txt", Source: "tmpl2"},
		{DestPath: "file3.txt", Source: "tmpl3"},
	}

	r := &Resolver{Force: true, Scanner: nil} // Scanner nil when Force is true

	result, err := r.BulkResolve(conflicts)
	if err != nil {
		t.Fatalf("BulkResolve returned error: %v", err)
	}

	for _, c := range conflicts {
		if !result[c.DestPath] {
			t.Errorf("expected true for %s with Force=true", c.DestPath)
		}
	}
}

func TestBulkResolve_S4_Abort(t *testing.T) {
	conflicts := []Conflict{
		{DestPath: "file1.txt", Source: "tmpl1"},
	}

	r := &Resolver{Force: false, Scanner: bufio.NewScanner(strings.NewReader("a\n"))}

	_, err := r.BulkResolve(conflicts)
	if err == nil {
		t.Fatal("expected error for abort, got nil")
	}

	if !strings.Contains(err.Error(), "aborted") {
		t.Errorf("expected 'aborted' in error, got: %v", err)
	}
}

func TestBulkResolve_SelectIndividually(t *testing.T) {
	conflicts := []Conflict{
		{DestPath: "file1.txt", Source: "tmpl1"},
		{DestPath: "file2.txt", Source: "tmpl2"},
	}

	// Select yes for file1, no for file2
	r := &Resolver{Force: false, Scanner: bufio.NewScanner(strings.NewReader("s\ny\nn\n"))}

	result, err := r.BulkResolve(conflicts)
	if err != nil {
		t.Fatalf("BulkResolve returned error: %v", err)
	}

	if !result["file1.txt"] {
		t.Errorf("expected true for file1.txt")
	}
	if result["file2.txt"] {
		t.Errorf("expected false for file2.txt")
	}
}

func TestBulkResolve_BulkNo(t *testing.T) {
	conflicts := []Conflict{
		{DestPath: "file1.txt", Source: "tmpl1"},
		{DestPath: "file2.txt", Source: "tmpl2"},
	}

	r := &Resolver{Force: false, Scanner: bufio.NewScanner(strings.NewReader("n\n"))}

	result, err := r.BulkResolve(conflicts)
	if err != nil {
		t.Fatalf("BulkResolve returned error: %v", err)
	}

	for _, c := range conflicts {
		if result[c.DestPath] {
			t.Errorf("expected false for %s with bulk 'n'", c.DestPath)
		}
	}
}
