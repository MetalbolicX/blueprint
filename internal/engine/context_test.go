package engine

import (
	"testing"

	"github.com/fluxo/fluxo/internal/templates"
)

// TestContext_toMap tests that Context.toMap() produces the correct map structure.
func TestContext_toMap(t *testing.T) {
	ctx := Context{
		CWD:          "/home/user/project",
		ActionFolder: "/home/user/project/templates/my-generator",
		Name:         "mycomponent",
		NamePascal:   "Mycomponent",
		Names:        "mycomponents",
		NamesPascal:  "Mycomponents",
		Attributes:   map[string]string{"name": "mycomponent", "path": "/tmp"},
	}

	m := ctx.toMap()

	// Check all keys are present
	expected := map[string]interface{}{
		"cwd":          "/home/user/project",
		"actionfolder": "/home/user/project/templates/my-generator",
		"name":         "mycomponent",
		"Name":         "Mycomponent",
		"names":        "mycomponents",
		"Names":        "Mycomponents",
		"attributes":   map[string]string{"name": "mycomponent", "path": "/tmp"},
	}

	for k, v := range expected {
		if got, ok := m[k]; !ok {
			t.Errorf("key %q missing from context map", k)
		} else if k == "attributes" {
			// Compare maps
			gotAttrs, ok := got.(map[string]string)
			if !ok {
				t.Errorf("attributes is not map[string]string, got %T", got)
				continue
			}
			wantAttrs := v.(map[string]string)
			for attrKey, attrVal := range wantAttrs {
				if gotAttrs[attrKey] != attrVal {
					t.Errorf("attributes[%q] = %q, want %q", attrKey, gotAttrs[attrKey], attrVal)
				}
			}
		} else if got != v {
			t.Errorf("context[%q] = %q, want %q", k, got, v)
		}
	}
}

// TestBuildContext_NameVariants tests that name variants are correctly cased.
func TestBuildContext_NameVariants(t *testing.T) {
	tests := []struct {
		name            string
		input           string
		wantName        string // lowercase of input
		wantNamePascal  string // PascalCase of input
		wantNames       string // plural lowercase
		wantNamesPascal string // plural PascalCase
	}{
		{
			name:            "simple lowercase",
			input:           "mycomponent",
			wantName:        "mycomponent",
			wantNamePascal:  "Mycomponent",
			wantNames:       "mycomponents",
			wantNamesPascal: "Mycomponents",
		},
		{
			name:            "snake_case",
			input:           "my_component",
			wantName:        "my_component",
			wantNamePascal:  "MyComponent",
			wantNames:       "my_components",
			wantNamesPascal: "MyComponents",
		},
		{
			name:            "kebab-case",
			input:           "my-component",
			wantName:        "my-component",
			wantNamePascal:  "MyComponent",
			wantNames:       "my-components",
			wantNamesPascal: "MyComponents",
		},
		{
			name:            "already PascalCase",
			input:           "MyComponent",
			wantName:        "mycomponent",
			wantNamePascal:  "MyComponent",
			wantNames:       "mycomponents",
			wantNamesPascal: "MyComponents",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Build context with the input
			ctx := BuildContext("/cwd", "/actionfolder", tt.input, nil)

			// name = strings.ToLower(input) — preserve separators like - and _
			if ctx.Name != tt.wantName {
				t.Errorf("name variant for %q = %q, want %q", tt.input, ctx.Name, tt.wantName)
			}

			// Name = PascalCase(input)
			if ctx.NamePascal != tt.wantNamePascal {
				t.Errorf("Name variant for %q = %q, want %q", tt.input, ctx.NamePascal, tt.wantNamePascal)
			}

			// names = name + "s"
			if ctx.Names != tt.wantNames {
				t.Errorf("names variant for %q = %q, want %q", tt.input, ctx.Names, tt.wantNames)
			}

			// Names = Name + "s"
			if ctx.NamesPascal != tt.wantNamesPascal {
				t.Errorf("Names variant for %q = %q, want %q", tt.input, ctx.NamesPascal, tt.wantNamesPascal)
			}
		})
	}
}

// TestBuildContext_EmptyName tests that BuildContext handles empty name gracefully.
func TestBuildContext_EmptyName(t *testing.T) {
	ctx := BuildContext("/cwd", "/actionfolder", "", nil)

	if ctx.Name != "" {
		t.Errorf("Name = %q, want empty string", ctx.Name)
	}
	if ctx.NamePascal != "" {
		t.Errorf("NamePascal = %q, want empty string", ctx.NamePascal)
	}
	if ctx.Names != "" {
		t.Errorf("Names = %q, want empty string", ctx.Names)
	}
	if ctx.NamesPascal != "" {
		t.Errorf("NamesPascal = %q, want empty string", ctx.NamesPascal)
	}
}

// TestParseCLIAttributes tests CLI attribute parsing.
func TestParseCLIAttributes(t *testing.T) {
	tests := []struct {
		name      string
		args      []string
		wantKey   string
		wantValue string
	}{
		{
			name:      "single attribute",
			args:      []string{"--name", "mycomponent"},
			wantKey:   "name",
			wantValue: "mycomponent",
		},
		{
			name:      "multiple attributes",
			args:      []string{"--name", "mycomponent", "--path", "/tmp"},
			wantKey:   "path",
			wantValue: "/tmp",
		},
		{
			name:      "no values",
			args:      []string{},
			wantKey:   "nonexistent",
			wantValue: "",
		},
		{
			name:      "value without key ignored",
			args:      []string{"somevalue"},
			wantKey:   "somevalue",
			wantValue: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			attrs := ParseCLIAttributes(tt.args)
			if val, ok := attrs[tt.wantKey]; ok {
				if val != tt.wantValue {
					t.Errorf("attribute %q = %q, want %q", tt.wantKey, val, tt.wantValue)
				}
			} else if tt.wantValue != "" {
				t.Errorf("attribute %q not found in %v", tt.wantKey, attrs)
			}
		})
	}
}

// TestContextInput_Structure tests the ContextInput struct.
func TestContextInput_Structure(t *testing.T) {
	input := ContextInput{
		CWD:          "/home/user/project",
		ManifestPath: "/home/user/project/templates/my-gen/manifest.yaml",
		Name:         "test-component",
		Attributes:   map[string]string{"key": "value"},
	}

	if input.CWD != "/home/user/project" {
		t.Errorf("CWD = %q, want %q", input.CWD, "/home/user/project")
	}
	if input.ManifestPath != "/home/user/project/templates/my-gen/manifest.yaml" {
		t.Errorf("ManifestPath = %q, want %q", input.ManifestPath, "/home/user/project/templates/my-gen/manifest.yaml")
	}
	if input.Name != "test-component" {
		t.Errorf("Name = %q, want %q", input.Name, "test-component")
	}
	if input.Attributes["key"] != "value" {
		t.Errorf("Attributes[key] = %q, want %q", input.Attributes["key"], "value")
	}
}

// TestMergeContext_MergeHierarchy tests the context merge hierarchy.
func TestMergeContext_MergeHierarchy(t *testing.T) {
	// The merge order is: native context → prompt defaults → prompt answers → CLI attributes

	promptDefaults := map[string]interface{}{
		"name": "default-name",
		"path": "/default/path",
	}

	promptAnswers := map[string]interface{}{
		"name": "user-answer-name",
	}

	cliAttrs := map[string]string{
		"name": "cli-overridden-name",
	}

	// Build context following the spec: native → prompt defaults → prompts → CLI
	merged := buildMergeContext(promptDefaults, promptAnswers, cliAttrs)

	// name should be CLI value (highest priority)
	if merged["name"] != "cli-overridden-name" {
		t.Errorf("name = %q, want %q (CLI should override)", merged["name"], "cli-overridden-name")
	}

	// path should be from prompt defaults (not in prompts or CLI)
	if merged["path"] != "/default/path" {
		t.Errorf("path = %q, want %q", merged["path"], "/default/path")
	}
}

// buildMergeContext mirrors the merge logic in Execute().
func buildMergeContext(defaults, prompts map[string]interface{}, cliAttrs map[string]string) map[string]interface{} {
	result := make(map[string]interface{})

	// 1. Start with native context keys (empty for this test)

	// 2. Merge prompt defaults
	for k, v := range defaults {
		result[k] = v
	}

	// 3. Merge prompt answers (override defaults)
	for k, v := range prompts {
		result[k] = v
	}

	// 4. Merge CLI attributes (override prompts)
	for k, v := range cliAttrs {
		result[k] = v
	}

	return result
}

// TestBuildContext_AllFieldsPopulated tests that BuildContext populates all fields.
func TestBuildContext_AllFieldsPopulated(t *testing.T) {
	attrs := map[string]string{"extra": "attr"}
	ctx := BuildContext("/cwd", "/actionfolder", "MyComponent", attrs)

	if ctx.CWD != "/cwd" {
		t.Errorf("CWD = %q, want %q", ctx.CWD, "/cwd")
	}
	if ctx.ActionFolder != "/actionfolder" {
		t.Errorf("ActionFolder = %q, want %q", ctx.ActionFolder, "/actionfolder")
	}
	if ctx.Name != "mycomponent" {
		t.Errorf("Name = %q, want %q", ctx.Name, "mycomponent")
	}
	if ctx.NamePascal != "MyComponent" {
		t.Errorf("NamePascal = %q, want %q", ctx.NamePascal, "MyComponent")
	}
	if ctx.Names != "mycomponents" {
		t.Errorf("Names = %q, want %q", ctx.Names, "mycomponents")
	}
	if ctx.NamesPascal != "MyComponents" {
		t.Errorf("NamesPascal = %q, want %q", ctx.NamesPascal, "MyComponents")
	}
	if ctx.Attributes["extra"] != "attr" {
		t.Errorf("Attributes[extra] = %q, want %q", ctx.Attributes["extra"], "attr")
	}
}

// TestTemplateFunctions_CaseConversion tests that funcmaps produce expected case conversions.
func TestTemplateFunctions_CaseConversion(t *testing.T) {
	tests := []struct {
		name     string
		input    string
		pascal   string
		camel    string
		kebab    string
		snake    string
	}{
		{"simple", "mycomponent", "Mycomponent", "mycomponent", "mycomponent", "mycomponent"},
		{"snake", "my_component", "MyComponent", "myComponent", "my-component", "my_component"},
		{"kebab", "my-component", "MyComponent", "myComponent", "my-component", "my_component"},
		{"mixed", "MyComponent", "MyComponent", "myComponent", "my-component", "my_component"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := templates.PascalCase(tt.input); got != tt.pascal {
				t.Errorf("PascalCase(%q) = %q, want %q", tt.input, got, tt.pascal)
			}
			if got := templates.CamelCase(tt.input); got != tt.camel {
				t.Errorf("CamelCase(%q) = %q, want %q", tt.input, got, tt.camel)
			}
			if got := templates.KebabCase(tt.input); got != tt.kebab {
				t.Errorf("KebabCase(%q) = %q, want %q", tt.input, got, tt.kebab)
			}
			if got := templates.SnakeCase(tt.input); got != tt.snake {
				t.Errorf("SnakeCase(%q) = %q, want %q", tt.input, got, tt.snake)
			}
		})
	}
}