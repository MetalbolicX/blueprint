// Package conflicts handles file collision detection and resolution.
package conflicts

import (
	"bufio"
	"errors"
	"fmt"
	"strings"
)

// Conflict represents a detected file collision.
type Conflict struct {
	DestPath string
	Source   string
}

// Resolver handles conflict resolution with optional force mode.
type Resolver struct {
	Force   bool
	Scanner *bufio.Scanner
}

// BulkResolve prompts the user for each conflict and returns a map of
// destPath -> true (overwrite) or false (skip).
// Supported responses: [y]es to all, [n]o to all, [s]elect individually, [a]bort
func (r *Resolver) BulkResolve(conflicts []Conflict) (map[string]bool, error) {
	// No conflicts — no prompt needed
	if len(conflicts) == 0 {
		result := make(map[string]bool)
		return result, nil
	}

	// If Force is set, auto-overwrite all without prompting
	if r.Force {
		result := make(map[string]bool)
		for _, c := range conflicts {
			result[c.DestPath] = true
		}
		return result, nil
	}

	return bulkPrompt(conflicts, r.Scanner)
}

// ErrAbort is returned when the user chooses to abort.
var ErrAbort = errors.New("aborted")

func bulkPrompt(conflicts []Conflict, scanner *bufio.Scanner) (map[string]bool, error) {
	result := make(map[string]bool)

	fmt.Println("[fluxo] File conflicts detected:")
	for _, c := range conflicts {
		fmt.Printf("  - %s (source: %s)\n", c.DestPath, c.Source)
	}
	fmt.Println()
	fmt.Println("Options: [y]es to all, [n]o to all, [s]elect individually, [a]bort")

	for {
		fmt.Print("> ")
		if !scanner.Scan() {
			return nil, fmt.Errorf("input closed")
		}
		response := strings.TrimSpace(strings.ToLower(scanner.Text()))

		switch response {
		case "y":
			for _, c := range conflicts {
				result[c.DestPath] = true
			}
			return result, nil
		case "n":
			for _, c := range conflicts {
				result[c.DestPath] = false
			}
			return result, nil
		case "s":
			return selectIndividually(conflicts, scanner)
		case "a":
			return nil, fmt.Errorf("%w: user chose abort", ErrAbort)
		default:
			fmt.Println("Invalid response. Use: y, n, s, or a")
		}
	}
}

func selectIndividually(conflicts []Conflict, scanner *bufio.Scanner) (map[string]bool, error) {
	result := make(map[string]bool)
	for _, c := range conflicts {
		fmt.Printf("  Overwrite %s? [y]es, [n]o: ", c.DestPath)
		if !scanner.Scan() {
			return nil, fmt.Errorf("input closed")
		}
		response := strings.TrimSpace(strings.ToLower(scanner.Text()))
		switch response {
		case "y":
			result[c.DestPath] = true
		case "n":
			result[c.DestPath] = false
		default:
			fmt.Println("Invalid response, skipping")
			result[c.DestPath] = false
		}
	}
	return result, nil
}
