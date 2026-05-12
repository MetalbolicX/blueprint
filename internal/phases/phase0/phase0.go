// Package phase0 handles prompt collection and conflict detection.
package phase0

import (
	"fmt"

	"github.com/fluxo/fluxo/internal/conflicts"
	"github.com/fluxo/fluxo/internal/discovery"
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

	// Copy prompt values through to resolved values
	for k, v := range input.PromptValues {
		output.ResolvedValues[k] = v
	}

	// Conflict detection will be enhanced when OutputRoot is available
	// For now, pass through without conflicts if no output dir specified

	return output, nil
}
