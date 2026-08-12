# Blueprint

A fast, transactional template generator — a modern replacement for Hygen.

Generate code, config files, or any text from templates with atomic commits, declarative prompts, and no runtime dependencies. **Language-agnostic** — the same engine drives TypeScript, Go, Python, Rust, SQL, YAML, or any text output.

```bash
npx blueprint generate react-component --name User --path src/components
```

## Installation

```bash
npm install -g blueprint
```

For non-installed use:

```bash
npx blueprint <command>
```

## Onboarding

Scaffold a runnable hello-world template in your project:

```bash
blueprint init
blueprint generate hello-world myfirst
```

Produces `hello-myfirst.md` in the current directory.

For global installation (templates stored in `~/.config/blueprint/`):

```bash
blueprint init --global
blueprint generate hello-world myfirst
```

Both commands are idempotent — re-running is safe and produces no changes.

## Quick start

1. **Init** — `blueprint init` scaffolds `.blueprint.yaml` and a hello-world example in `_templates/hello-world/`
2. **Author** — create a manifest + template files:

```bash
_templates/
└── component/
    └── new/
        ├── manifest.yaml
        └── files/
            └── Component.tsx.ejs.t
```

```yaml
# manifest.yaml
name: component
classification: component
prompts:
  - name: name
    type: input
    description: "Component name (PascalCase)"
    default: MyComponent
  - name: path
    type: input
    description: "Output path"
    default: src/components
```

```yaml
# files/Component.tsx.ejs.t
---
to: <%= path %>/<%= name %>.tsx
---
import React from 'react'

interface <%= name %>Props {
  children?: React.ReactNode
}

export const <%= name %>: React.FC<<%= name %>Props> = ({ children }) => {
  return <div className="<%= h.kebabCase(name) %>"><%= children %></div>
}
```

3. **Generate** — `blueprint generate component --name Button --path src/ui`

## CLI usage

```bash
# Show help
blueprint --help

# Scaffold .blueprint.yaml
blueprint init

# Generate from a template classification
blueprint generate <classification> [options]

# Options:
#   --name <name>     Component name (PascalCase)
#   -n, --name <name> Short form
#   --force           Skip prompts, overwrite existing files
#   -f, --force       Short form
#   --output <dir>    Output directory
#   -o, --output <dir> Short form
#   --<key> <value>   Arbitrary attributes passed to templates
 
# Template registry management
# blueprint template copy <classification>      Copy a project generator into global registry
# blueprint template list                      List registry entries (name + source path)
# blueprint template remove <classification>   Remove a global template and its registry entry
```

### Examples

```bash
# Basic generation with prompts
blueprint generate react-component

# With explicit name (skips name prompt)
blueprint generate react-component --name Button

# Force overwrite existing files
blueprint generate react-component --name Button --force

# Custom output directory
blueprint generate react-component --name Button --output src/ui

# Pass custom attributes
blueprint generate react-component --name Button --path src/components --framework react18

# Use short flags
blueprint generate react-component -n Button -f -o src/ui
```

## Template format

### `manifest.yaml`

Declares metadata, classification, and interactive prompts:

```yaml
name: component
classification: component
prompts:
  - name: package
    type: input
    description: "Package or module name"
    default: main
  - name: framework
    type: select
    description: "Framework"
    options:
      - react
      - vue
      - svelte
  - name: includeTests
    type: confirm
    description: "Include test file?"
    default: true
```

### Template files (`*.ejs.t`)

Frontmatter defines the operation; body is the template. Uses EJS syntax.

```yaml
---
to: src/<%= name %>.tsx
inject: React.FC<<%= name %>Props>
---
import React from 'react'

interface <%= name %>Props {
  children?: React.ReactNode
}

export const <%= name %>: React.FC<<%= name %>Props> = ({ children }) => {
  return <div className="<%= h.kebabCase(name) %>"><%= children %></div>
}
```

## Frontmatter directives

| Directive | Type | Description |
|-----------|------|-------------|
| `to` | string | Target file path |
| `inject` | string | Regex pattern to match for replacement |
| `after` | string | Regex — insert content after this pattern |
| `before` | string | Regex — insert content before this pattern |
| `prepend` | bool | Prepend content to existing file |
| `append` | bool | Append content to existing file |
| `force` | bool | Overwrite existing file |
| `sh` | string | Shell command to execute after render |

### Directive examples

**to** — Write to a specific path:
```yaml
---
to: src/<%= name %>.tsx
---
```

**inject** — Replace content matching a regex:
```yaml
---
inject: const \w+ = new
---
const newInstance = new Constructor()
```

**after** — Insert after a regex match:
```yaml
---
after: class \w+
---
  // Added after class definition
```

**before** — Insert before a regex match:
```yaml
---
before: export default
---
// Header comment
```

**prepend** — Add to the beginning of a file:
```yaml
---
prepend: true
---
// This goes at the top
```

**append** — Add to the end of a file:
```yaml
---
append: true
---
// This goes at the bottom
```

**force** — Overwrite without prompting:
```yaml
---
to: src/<%= name %>.tsx
force: true
---
```

**script** — Run a configured script after render:
```yaml
---
to: src/<%= name %>.tsx
script: setup
---
```

## Context variables

Available inside every template via EJS:

| Variable | Description |
|----------|-------------|
| `<%= name %>` | Component name (lowercase) |
| `<%= Name %>` | Component name (PascalCase) |
| `<%= names %>` | Pluralized lowercase |
| `<%= Names %>` | Pluralized PascalCase |
| `<%= path %>` | User-provided `path` attribute |
| `<%= package %>` | User-provided `package` attribute |
| Any prompt answer | Available by its name |

## FuncMaps (template helpers)

Available as `h.*` in templates:

| Function | Example | Result |
|----------|---------|--------|
| `h.pascalCase(str)` | `<%= h.pascalCase("hello_world") %>` | `HelloWorld` |
| `h.camelCase(str)` | `<%= h.camelCase("hello_world") %>` | `helloWorld` |
| `h.kebabCase(str)` | `<%= h.kebabCase("HelloWorld") %>` | `hello-world` |
| `h.snakeCase(str)` | `<%= h.snakeCase("HelloWorld") %>` | `hello_world` |
| `h.upper(str)` | `<%= h.upper("hello") %>` | `HELLO` |
| `h.lower(str)` | `<%= h.lower("HELLO") %>` | `hello` |
| `h.trim(str)` | `<%= h.trim("  hello  ") %>` | `hello` |
| `h.title(str)` | `<%= h.title("hello world") %>` | `Hello World` |

## Hooks

Lifecycle hooks in `.blueprint.yaml`:

```yaml
hooks:
  pre_generate: echo "Starting generation..."
  post_generate: prettier --write generated/
  timeout: 30s
```

Supported interpreters: `bash`, `sh`, `node`, `python3`, `pwsh`.

## Safety

- **Transactional**: renders to temp staging dir, commits atomically — no partial writes
- **Rollback**: on any failure (render error, shell error), staged files are cleaned up
- **Conflict resolution**: bulk prompt — `[y]es to all, [n]o to all, [s]elect individually, [a]bort`

## Global template registry

- Template registry entries are stored in `~/.config/blueprint/config.yaml` under the `registry` array. Each entry records `name`, `source` (absolute path to the original project generator), and `path` (the installed `~/.config/blueprint/templates/<name>/` location).
- `blueprint template copy <classification>` copies the entire source generator directory (manifest + actions) into the registry folder and persists the entry.
- `blueprint template list` shows installed templates and their originating paths.
- `blueprint template remove <classification>` deletes the registry directory and removes the associated config entry.
- Discovery automatically appends registry paths after the project’s `_templates/templates/generators` stack, so local generators still win when a name conflicts.

## Local release

Publish from a clean worktree to avoid shipping unintended files:

```bash
git stash                 # or git checkout -- .
pnpm build                # ReScript compile + rolldown bundle
pnpm res:test             # full test suite
npm pack --dry-run        # inspect the exact file list
npm publish --access public
git tag v<version>
git push --tags
```

## Docs

Full documentation at [/docs](/docs), including architecture, API reference, and tutorials.
