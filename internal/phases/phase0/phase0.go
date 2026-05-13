// Package phase0 handles prompt collection and conflict detection.
package phase0

import (
	"bufio"
	"fmt"
	"os"

	"github.com/fluxo/fluxo/internal/conflicts"
	"github.com/fluxo/fluxo/internal/discovery"
	"github.com/fluxo/fluxo/internal/manifest"
)

// Phase0Input is the input for Phase 0.
type Phase0Input struct {
	Index        discovery.TemplateIndex
	PromptValues map[string]interface{}
	Force        bool
}

// Phase0Output is the output from Phase 0.
type Phase0Output struct {
	ResolvedValues map[string]interface{}
	Conflicts      []conflicts.Conflict
}

// Execute collects prompt values, detects file conflicts, and resolves them.
func Execute(input Phase0Input) (*Phase0Output, error) {
	if input.Index == nil {
		return nil, fmt.Errorf("Index is required")
	}

	output := &Phase0Output{
		ResolvedValues: make(map[string]interface{}),
		Conflicts:      nil,
	}

	// Collect all prompts from the index
	var allPrompts []manifest.Prompt
	for _, entry := range input.Index {
		if entry.Manifest != nil {
			allPrompts = append(allPrompts, entry.Manifest.Prompts...)
		}
	}

	// Resolve prompts
	if input.Force {
		// Force mode: apply defaults for missing values without prompting
		for _, p := range allPrompts {
			if _, exists := output.ResolvedValues[p.Name]; !exists {
				if p.Default != nil {
					output.ResolvedValues[p.Name] = p.Default
				}
			}
		}
	} else {
		// Interactive mode: prompt for missing values
		scanner := bufio.NewScanner(os.Stdin)
		resolved, err := ResolvePrompts(allPrompts, input.PromptValues, scanner)
		if err != nil {
			return nil, fmt.Errorf("prompt resolution failed: %w", err)
		}
		output.ResolvedValues = resolved
	}

	// Conflict detection will be enhanced when OutputRoot is available
	// For now, pass through without conflicts if no output dir specified

	return output, nil
}
