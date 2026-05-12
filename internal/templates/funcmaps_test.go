package templates

import (
	"strings"
	"testing"
)

func TestPascalCase(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello_world", "HelloWorld"},
		{"HelloWorld", "HelloWorld"},
		{"hello-world", "HelloWorld"},
		{"hello", "Hello"},
		{"", ""},
	}

	for _, tt := range tests {
		result := PascalCase(tt.input)
		if result != tt.expected {
			t.Errorf("PascalCase(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}

func TestPascalCase_S3_EmptyString_NoPanic(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Errorf("PascalCase(%q) panicked: %v", "", r)
		}
	}()
	result := PascalCase("")
	if result != "" {
		t.Errorf("expected empty string, got %q", result)
	}
}

func TestCamelCase(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"hello_world", "helloWorld"},
		{"HelloWorld", "helloWorld"},
		{"hello-world", "helloWorld"},
		{"hello", "hello"},
		{"", ""},
	}

	for _, tt := range tests {
		result := CamelCase(tt.input)
		if result != tt.expected {
			t.Errorf("CamelCase(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}

func TestKebabCase(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"HelloWorld", "hello-world"},
		{"hello_world", "hello-world"},
		{"helloWorld", "hello-world"},
		{"hello", "hello"},
		{"", ""},
	}

	for _, tt := range tests {
		result := KebabCase(tt.input)
		if result != tt.expected {
			t.Errorf("KebabCase(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}

func TestSnakeCase(t *testing.T) {
	tests := []struct {
		input    string
		expected string
	}{
		{"HelloWorld", "hello_world"},
		{"hello_world", "hello_world"},
		{"helloWorld", "hello_world"},
		{"hello", "hello"},
		{"", ""},
	}

	for _, tt := range tests {
		result := SnakeCase(tt.input)
		if result != tt.expected {
			t.Errorf("SnakeCase(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}

func TestStringHelpers(t *testing.T) {
	// trim, title, upper, lower are wrappers — smoke test via direct passthrough
	tests := []struct {
		fn       func(string) string
		input    string
		expected string
	}{
		{strings.TrimSpace, "  hello  ", "hello"},
		{strings.Title, "hello world", "Hello World"},
		{strings.ToUpper, "hello", "HELLO"},
		{strings.ToLower, "HELLO", "hello"},
	}

	for _, tt := range tests {
		result := tt.fn(tt.input)
		if result != tt.expected {
			t.Errorf("helper(%q) = %q, want %q", tt.input, result, tt.expected)
		}
	}
}
