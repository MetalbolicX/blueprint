// Package templates provides template parsing and FuncMap utilities.
package templates

// Template represents a single template file with parsed frontmatter.
type Template struct {
	Path        string
	Frontmatter *Directives
	Content     string // raw template content (no frontmatter)
}

// Directives are template-level rendering instructions parsed from frontmatter.
type Directives struct {
	To      string // target path relative to output root
	Inject  string // regex pattern for injection point
	After   string // inject after this pattern
	Before  string // inject before this pattern
	Prepend bool   // prepend to file
	Append  bool   // append to file
	Force   bool   // overwrite existing
	Sh      string // shell command to run post-render
}
