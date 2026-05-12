// Package templates provides template parsing and FuncMap utilities.
package templates

import (
	"strings"
	"text/template"
	"unicode"
)

// PascalCase converts a string to PascalCase.
// Example: "hello_world" → "HelloWorld"
func PascalCase(s string) string {
	if s == "" {
		return ""
	}
	parts := splitIntoWords(s)
	for i, p := range parts {
		if len(p) == 0 {
			continue
		}
		parts[i] = strings.ToUpper(p[:1]) + strings.ToLower(p[1:])
	}
	return strings.Join(parts, "")
}

// CamelCase converts a string to camelCase.
// Example: "hello_world" → "helloWorld"
func CamelCase(s string) string {
	if s == "" {
		return ""
	}
	parts := splitIntoWords(s)
	for i, p := range parts {
		if len(p) == 0 {
			continue
		}
		if i == 0 {
			parts[i] = strings.ToLower(p)
		} else {
			parts[i] = strings.ToUpper(p[:1]) + strings.ToLower(p[1:])
		}
	}
	return strings.Join(parts, "")
}

// KebabCase converts a string to kebab-case.
// Example: "HelloWorld" → "hello-world"
func KebabCase(s string) string {
	if s == "" {
		return ""
	}
	parts := splitIntoWords(s)
	for i, p := range parts {
		if len(p) == 0 {
			continue
		}
		parts[i] = strings.ToLower(p)
	}
	return strings.Join(parts, "-")
}

// SnakeCase converts a string to snake_case.
// Example: "HelloWorld" → "hello_world"
func SnakeCase(s string) string {
	if s == "" {
		return ""
	}
	parts := splitIntoWords(s)
	for i, p := range parts {
		parts[i] = strings.ToLower(p)
	}
	return strings.Join(parts, "_")
}

// splitIntoWords splits a string on underscores, hyphens, and camelCase boundaries.
func splitIntoWords(s string) []string {
	var words []string
	var current strings.Builder
	for i, r := range s {
		if r == '_' || r == '-' {
			if current.Len() > 0 {
				words = append(words, current.String())
				current.Reset()
			}
			continue
		}
		if unicode.IsUpper(r) {
			if current.Len() > 0 {
				// If previous char was lowercase, this starts a new word
				if i > 0 {
					prev := rune(s[i-1])
					if unicode.IsLower(prev) || unicode.IsDigit(prev) {
						words = append(words, current.String())
						current.Reset()
					}
				}
			}
		}
		current.WriteRune(r)
	}
	if current.Len() > 0 {
		words = append(words, current.String())
	}
	return words
}

// RegisterFuncMaps returns a template.FuncMap with all registered functions.
func RegisterFuncMaps() template.FuncMap {
	return template.FuncMap{
		"pascalCase": PascalCase,
		"camelCase":  CamelCase,
		"kebabCase":  KebabCase,
		"snakeCase":  SnakeCase,
		"trim":       strings.TrimSpace,
		"title":      strings.Title,
		"upper":      strings.ToUpper,
		"lower":      strings.ToLower,
	}
}
