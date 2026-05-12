package templates

import (
	"fmt"
	"regexp"
	"strings"
)

// ParseFrontmatter extracts ---key: value--- blocks from the top of a file.
// It returns the parsed Directives, the remaining content after the frontmatter,
// and an error if the frontmatter is malformed.
func ParseFrontmatter(content string) (*Directives, string, error) {
	// Pattern: --- at start of line, followed by key: value lines, then --- at start of line
	frontmatterRegex := regexp.MustCompile(`(?m)^---\n((?:[^\n]*\n)*?)---\n?`)
	matches := frontmatterRegex.FindStringSubmatch(content)
	if matches == nil {
		// No frontmatter found — return empty directives and original content
		return &Directives{}, content, nil
	}

	frontmatterBody := matches[1]
	remaining := content[len(matches[0]):]

	d := &Directives{}

	// Parse each line as key: value
	for _, line := range strings.Split(frontmatterBody, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}

		kv := strings.SplitN(line, ":", 2)
		if len(kv) != 2 {
			return nil, "", fmt.Errorf("malformed frontmatter line: %q", line)
		}

		key := strings.TrimSpace(kv[0])
		value := strings.TrimSpace(kv[1])

		switch key {
		case "to":
			d.To = value
		case "inject":
			d.Inject = value
		case "after":
			d.After = value
		case "before":
			d.Before = value
		case "prepend":
			d.Prepend = value == "true" || value == "yes" || value == "1"
		case "append":
			d.Append = value == "true" || value == "yes" || value == "1"
		case "force":
			d.Force = value == "true" || value == "yes" || value == "1"
		case "sh":
			d.Sh = value
		default:
			// Unknown key — ignore for forward compatibility
		}
	}

	return d, remaining, nil
}

// ApplyInjection applies injection content to a target based on mode and inject pattern.
// Modes: "replace", "after", "before", "prepend", "append"
func ApplyInjection(target, injectPattern, content string, mode string) (string, error) {
	switch mode {
	case "prepend":
		return content + target, nil
	case "append":
		return target + content, nil
	case "replace", "after", "before":
		if injectPattern == "" {
			return "", fmt.Errorf("inject pattern required for mode %q", mode)
		}
		pattern := regexp.MustCompile(injectPattern)
		switch mode {
		case "replace":
			return pattern.ReplaceAllString(target, content), nil
		case "after":
			return pattern.ReplaceAllString(target, "$0"+content), nil
		case "before":
			return pattern.ReplaceAllString(target, content+"$0"), nil
		}
	default:
		return "", fmt.Errorf("unknown injection mode: %q", mode)
	}
	return target, nil
}
