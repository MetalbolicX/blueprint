# API Reference

## CLI

### `blueprint init`

Scaffolds a default `.blueprint.yaml` in the current directory.

```bash
blueprint init
```

### `blueprint generate <classification>`

Runs the generation pipeline for the given classification.

```bash
blueprint generate <classification> [flags]
```

#### Flags

| Flag | Type | Default | Description |
|------|------|---------|-------------|
| `--name` | string | `""` | Component name (generates name variants) |
| `--force` | bool | `false` | Skip prompts, overwrite existing files |
| `--output` | string | `generated` | Output root directory |
| `--help` | bool | `false` | Show usage |

---

## Manifest format

Schema for `manifest.yaml`:

```yaml
name: <string>              # Required: generator name
classification: <string>    # Required: used to match with `blueprint generate <classification>`
metadata:                   # Optional: arbitrary key-value pairs
  key: value
prompts:                    # Optional: declarative prompts
  - name: <string>          # Required: template variable name
    type: <input|select|confirm>
    description: <string>   # Shown to the user during interactive mode
    default: <any>          # Used when --force or user presses Enter
    options:                # Required for type: select
      - <string>
```

---

## Template files

Files in the `files/` subdirectory relative to `manifest.yaml`. Extensions: `.ejs.t` or `.tmpl`.

### Frontmatter

A `---`-delimited YAML block at the top of the file.

```yaml
---
to: output/path.txt
---
```

### Directives

| Directive | Type | Applies to | Description |
|-----------|------|-----------|-------------|
| `to` | string | create | Output file path |
| `inject` | string | inject | Regex pattern — target marked for replacement |
| `after` | string | inject | Regex pattern — insert rendered content after match |
| `before` | string | inject | Regex pattern — insert rendered content before match |
| `prepend` | bool | inject | Prepend rendered content to existing file |
| `append` | bool | inject | Append rendered content to existing file |
| `force` | bool | all | Overwrite existing file without confirmation |
| `sh` | string | shell | Command to execute after rendering |

### Injection modes

When `inject`, `after`, `before`, `prepend`, or `append` is set, the template modifies an existing file instead of creating a new one. The target file path is resolved from `to` (or the template's relative path if `to` is absent).

| Mode | Behavior | `inject` pattern required |
|------|----------|--------------------------|
| `inject:` | Replace matched text with rendered content | Yes |
| `after:` | Insert rendered content after the first match | Yes |
| `before:` | Insert rendered content before the first match | Yes |
| `prepend: true` | Prepend rendered content to file start | No |
| `append: true` | Append rendered content to file end | No |

### Example

```yaml
---
to: src/handlers/<%= h.pascalCase(Name) %>.go
force: true
---
package handlers

import "fmt"

func <%= Name %>Handler(w http.ResponseWriter, r *http.Request) {
    fmt.Fprintf(w, "<%= name %> endpoint")
}
```

---

## Context variables

Available in every template by default.

| Key | Type | Description |
|-----|------|-------------|
| `<%= cwd %>` | string | Working directory where blueprint was invoked |
| `<%= actionfolder %>` | string | Absolute path to the generator's manifest directory |
| `<%= name %>` | string | Component name (lowercased, from `--name` or prompt) |
| `<%= Name %>` | string | PascalCased component name |
| `<%= names %>` | string | Pluralized lowercase (`name + "s"`) |
| `<%= Names %>` | string | Pluralized PascalCase (`Name + "s"`) |
| `*merged*` | map | CLI attributes merged as individual variables |
| `<%= promptName %>` | any | Resolved prompt value by name |

**Priority (highest wins):** CLI attributes > prompt answers > prompt defaults > native defaults

---

## FuncMaps

Template helper functions available via the `h.*` prefix in EJS templates.

| Function | Input | Output |
|----------|-------|--------|
| `pascalCase` | `hello_world` | `HelloWorld` |
| `camelCase` | `hello_world` | `helloWorld` |
| `kebabCase` | `HelloWorld` | `hello-world` |
| `snakeCase` | `HelloWorld` | `hello_world` |
| `upper` | `hello` | `HELLO` |
| `lower` | `HELLO` | `hello` |
| `trim` | `" hello "` | `"hello"` |
| `title` | `hello world` | `Hello World` |

---

## `.blueprint.yaml`

```yaml
generators:
  - name: <string>
    classification: <string>
    template_root: <string>
    output_root: <string>
hooks:
  pre_generate: <string>     # Shell command, runs before generation
  post_generate: <string>    # Shell command, runs after generation
  timeout: <duration>        # e.g. "30s", "5m" (default: 5s)
```

## Global configuration

`~/.config/blueprint/config.yaml` applies to all projects. Project-level `.blueprint.yaml` values override global ones where applicable.

\`\`\`yaml
# Template search paths (discovered in addition to _templates/)
templates:
  - ~/my-org/shared-templates

# Allow shell commands in templates (default: false)
allow_dangerous_commands: false

# Force overwrite existing files without prompting (default: false)
force_overwrite: false

# Dry-run mode — render but don't write files (default: false)
dry_run: false

# Default timeout for hooks in seconds (default: 5)
timeout: 10

# Default CLI attributes — merged into every generation
default_attributes:
  organization: acme-corp
  license: MIT
\`\`\`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| \`templates\` | array | \`[]\` | Additional template search paths |
| \`allow_dangerous_commands\` | bool | \`false\` | Allow legacy shell execution |
| \`force_overwrite\` | bool | \`false\` | Skip prompts, overwrite existing files |
| \`dry_run\` | bool | \`false\` | Render templates without writing output |
| \`timeout\` | int | \`5\` | Hook execution timeout in seconds |
| \`default_attributes\` | dict | \`{}\` | Default CLI attributes for all generations |

---

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error (manifest not found, render failure, shell failure) |
