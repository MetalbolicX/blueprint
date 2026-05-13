package phase0

import (
	"bufio"
	"strings"
	"testing"

	"github.com/fluxo/fluxo/internal/manifest"
)

func TestResolvePrompts_Input(t *testing.T) {
	// User enters "my-name" for the input prompt
	scanner := bufio.NewScanner(strings.NewReader("my-name\n"))

	prompts := []manifest.Prompt{
		{Name: "name", Type: "input", Description: "Project name:", Default: nil},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["name"] != "my-name" {
		t.Errorf("expected 'my-name', got %v", result["name"])
	}
}

func TestResolvePrompts_Input_UsesDefaultWhenProvided(t *testing.T) {
	// No input needed — value already present
	scanner := bufio.NewScanner(strings.NewReader(""))

	prompts := []manifest.Prompt{
		{Name: "name", Type: "input", Description: "Project name:", Default: "default-name"},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["name"] != "default-name" {
		t.Errorf("expected 'default-name', got %v", result["name"])
	}
}

func TestResolvePrompts_Select(t *testing.T) {
	// User selects option 2
	scanner := bufio.NewScanner(strings.NewReader("2\n"))

	prompts := []manifest.Prompt{
		{Name: "lang", Type: "select", Description: "Select language:", Options: []string{"go", "rust", "typescript"}},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["lang"] != "rust" {
		t.Errorf("expected 'rust', got %v", result["lang"])
	}
}

func TestResolvePrompts_Select_InvalidNumberUsesDefault(t *testing.T) {
	// Invalid input followed by valid selection
	scanner := bufio.NewScanner(strings.NewReader("99\n1\n"))

	prompts := []manifest.Prompt{
		{Name: "lang", Type: "select", Description: "Select language:", Options: []string{"go", "rust", "typescript"}, Default: "go"},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["lang"] != "go" {
		t.Errorf("expected 'go' (default), got %v", result["lang"])
	}
}

func TestResolvePrompts_Confirm(t *testing.T) {
	// User confirms with "y"
	scanner := bufio.NewScanner(strings.NewReader("y\n"))

	prompts := []manifest.Prompt{
		{Name: "confirm", Type: "confirm", Description: "Proceed?"},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["confirm"] != true {
		t.Errorf("expected true, got %v", result["confirm"])
	}
}

func TestResolvePrompts_Confirm_Negative(t *testing.T) {
	// User declines with "n"
	scanner := bufio.NewScanner(strings.NewReader("n\n"))

	prompts := []manifest.Prompt{
		{Name: "confirm", Type: "confirm", Description: "Proceed?"},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["confirm"] != false {
		t.Errorf("expected false, got %v", result["confirm"])
	}
}

func TestResolvePrompts_Confirm_UsesDefaultWhenProvided(t *testing.T) {
	// No input needed — value already present
	scanner := bufio.NewScanner(strings.NewReader(""))

	prompts := []manifest.Prompt{
		{Name: "confirm", Type: "confirm", Description: "Proceed?", Default: true},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["confirm"] != true {
		t.Errorf("expected true (default), got %v", result["confirm"])
	}
}

func TestResolvePrompts_MultiplePrompts(t *testing.T) {
	// User provides name (input), selects option 2 (select), and confirms yes
	scanner := bufio.NewScanner(strings.NewReader("my-project\n2\ny\n"))

	prompts := []manifest.Prompt{
		{Name: "name", Type: "input", Description: "Project name:"},
		{Name: "lang", Type: "select", Description: "Select language:", Options: []string{"go", "rust", "typescript"}},
		{Name: "proceed", Type: "confirm", Description: "Proceed?"},
	}
	values := map[string]interface{}{}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["name"] != "my-project" {
		t.Errorf("expected 'my-project', got %v", result["name"])
	}
	if result["lang"] != "rust" {
		t.Errorf("expected 'rust', got %v", result["lang"])
	}
	if result["proceed"] != true {
		t.Errorf("expected true, got %v", result["proceed"])
	}
}

func TestResolvePrompts_PreservesExistingValues(t *testing.T) {
	// "name" is already provided in values, so scanner only needs input for "lang" and "proceed"
	// The first line "2" is consumed by resolveSelect for "lang"
	// The second line "n" is consumed by resolveConfirm for "proceed"
	scanner := bufio.NewScanner(strings.NewReader("2\nn\n"))

	prompts := []manifest.Prompt{
		{Name: "name", Type: "input", Description: "Project name:"},
		{Name: "lang", Type: "select", Description: "Select language:", Options: []string{"go", "rust"}},
		{Name: "proceed", Type: "confirm", Description: "Proceed?"},
	}
	values := map[string]interface{}{
		"name": "existing-name",
	}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["name"] != "existing-name" {
		t.Errorf("expected 'existing-name', got %v", result["name"])
	}
	// lang and proceed should still be resolved since they're missing
	if result["lang"] != "rust" {
		t.Errorf("expected 'rust', got %v", result["lang"])
	}
	if result["proceed"] != false {
		t.Errorf("expected false, got %v", result["proceed"])
	}
}

func TestResolvePrompts_EmptyPrompts(t *testing.T) {
	scanner := bufio.NewScanner(strings.NewReader(""))
	prompts := []manifest.Prompt{}
	values := map[string]interface{}{"existing": "value"}

	result, err := ResolvePrompts(prompts, values, scanner)
	if err != nil {
		t.Fatalf("ResolvePrompts returned error: %v", err)
	}

	if result["existing"] != "value" {
		t.Errorf("expected 'value', got %v", result["existing"])
	}
	if len(result) != 1 {
		t.Errorf("expected 1 key, got %d", len(result))
	}
}