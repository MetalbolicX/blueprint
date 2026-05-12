package templates

import (
	"testing"
)

func TestParseFrontmatter_S1_ToDirective(t *testing.T) {
	content := "---\nto: out.txt\n---\nHello, World!"
	directives, remaining, err := ParseFrontmatter(content)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if directives == nil {
		t.Fatal("expected non-nil Directives")
	}
	if directives.To != "out.txt" {
		t.Errorf("expected directives.To %q, got %q", "out.txt", directives.To)
	}
	if remaining != "Hello, World!" {
		t.Errorf("expected remaining content %q, got %q", "Hello, World!", remaining)
	}
}

func TestParseFrontmatter_S2_InjectMode(t *testing.T) {
	content := "---\ninject: pattern\n---\nHello"
	directives, _, err := ParseFrontmatter(content)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if directives.Inject != "pattern" {
		t.Errorf("expected directives.Inject %q, got %q", "pattern", directives.Inject)
	}
}

func TestParseFrontmatter_S3_PrependMode(t *testing.T) {
	content := "---\nprepend: true\n---\nPrepended content"
	directives, _, err := ParseFrontmatter(content)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if !directives.Prepend {
		t.Error("expected directives.Prepend to be true")
	}
}

func TestApplyInjection_AfterMode(t *testing.T) {
	target := "line1\nPATTERN\nline3"
	injectPattern := "PATTERN"
	content := "\nINJECTED"
	result, err := ApplyInjection(target, injectPattern, content, "after")
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	// Content should be injected AFTER the pattern match
	expected := "line1\nPATTERN\nINJECTED\nline3"
	if result != expected {
		t.Errorf("expected %q, got %q", expected, result)
	}
}

func TestApplyInjection_PrependMode(t *testing.T) {
	target := "Existing content"
	content := "New content"
	result, err := ApplyInjection(target, "", content, "prepend")
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	expected := "New contentExisting content"
	if result != expected {
		t.Errorf("expected %q, got %q", expected, result)
	}
}

func TestParseFrontmatter_NoFrontmatter(t *testing.T) {
	content := "Just regular content"
	directives, remaining, err := ParseFrontmatter(content)
	if err != nil {
		t.Fatalf("expected nil error, got %v", err)
	}
	if directives.To != "" {
		t.Errorf("expected empty To, got %q", directives.To)
	}
	if remaining != content {
		t.Errorf("expected remaining %q, got %q", content, remaining)
	}
}
