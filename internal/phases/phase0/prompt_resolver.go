// Package phase0 handles prompt collection and conflict detection.
package phase0

import (
	"bufio"
	"fmt"
	"strings"

	"github.com/fluxo/fluxo/internal/manifest"
)

// ResolvePrompts interactively resolves missing prompt values.
// It copies existing values from values map, then prompts for any missing ones.
// Returns a map of resolved values.
func ResolvePrompts(prompts []manifest.Prompt, values map[string]interface{}, scanner *bufio.Scanner) (map[string]interface{}, error) {
	result := make(map[string]interface{})

	// Copy existing values
	for k, v := range values {
		result[k] = v
	}

	// Resolve each prompt
	for _, p := range prompts {
		if _, exists := result[p.Name]; exists {
			// Value already provided, skip
			continue
		}

		// Check if prompt has a default and no interactive input needed
		if p.Default != nil {
			result[p.Name] = p.Default
			continue
		}

		// Prompt interactively based on type
		switch p.Type {
		case "input":
			val, err := resolveInput(p, scanner)
			if err != nil {
				return nil, err
			}
			result[p.Name] = val

		case "select":
			val, err := resolveSelect(p, scanner)
			if err != nil {
				return nil, err
			}
			result[p.Name] = val

		case "confirm":
			val, err := resolveConfirm(p, scanner)
			if err != nil {
				return nil, err
			}
			result[p.Name] = val
		}
	}

	return result, nil
}

func resolveInput(p manifest.Prompt, scanner *bufio.Scanner) (string, error) {
	fmt.Print(p.Description)
	if p.Default != nil {
		fmt.Printf(" (default: %v)", p.Default)
	}
	fmt.Print(" ")

	if !scanner.Scan() {
		return "", fmt.Errorf("input closed")
	}
	text := scanner.Text()

	if text == "" && p.Default != nil {
		return fmt.Sprintf("%v", p.Default), nil
	}
	return text, nil
}

func resolveSelect(p manifest.Prompt, scanner *bufio.Scanner) (string, error) {
	fmt.Println(p.Description)
	for i, opt := range p.Options {
		fmt.Printf("  %d. %s\n", i+1, opt)
	}
	if p.Default != nil {
		fmt.Printf("  (default: %v)\n", p.Default)
	}
	fmt.Print("> ")

	if !scanner.Scan() {
		return "", fmt.Errorf("input closed")
	}
	text := strings.TrimSpace(scanner.Text())

	// Try to parse as number
	var idx int
	if _, err := fmt.Sscanf(text, "%d", &idx); err == nil {
		if idx >= 1 && idx <= len(p.Options) {
			return p.Options[idx-1], nil
		}
	}

	// Invalid selection, use default if available
	if p.Default != nil {
		return fmt.Sprintf("%v", p.Default), nil
	}

	// Default to first option as fallback
	return p.Options[0], nil
}

func resolveConfirm(p manifest.Prompt, scanner *bufio.Scanner) (bool, error) {
	fmt.Print(p.Description)
	if p.Default != nil {
		if def, ok := p.Default.(bool); ok {
			if def {
				fmt.Print(" [Y/n]")
			} else {
				fmt.Print(" [y/N]")
			}
		}
	}
	fmt.Print(" ")

	if !scanner.Scan() {
		return false, fmt.Errorf("input closed")
	}
	text := strings.TrimSpace(strings.ToLower(scanner.Text()))

	if text == "" {
		if p.Default != nil {
			if def, ok := p.Default.(bool); ok {
				return def, nil
			}
		}
		return false, nil
	}

	switch text {
	case "y", "yes":
		return true, nil
	case "n", "no":
		return false, nil
	default:
		// Invalid response, use default or false
		if p.Default != nil {
			if def, ok := p.Default.(bool); ok {
				return def, nil
			}
		}
		return false, nil
	}
}
