# Fluxo

A fast, transactional template generator — a modern replacement for Hygen.

Generate code, config files, or any text from templates with atomic commits, declarative prompts, and no runtime dependencies. **Language-agnostic** — the same engine drives Go, TypeScript, Python, Rust, SQL, YAML, or any text output.

```bash
fluxo generate component --name User --force --output src/
```

> [!Tip|style:flat|label=Any language]
> Fluxo templates output plain text. Go examples here are just one use case. Scroll for TypeScript, Python, and everything in between.

## Quick path

1. **Install** — `go install github.com/fluxo/fluxo/cmd/fluxo@latest`
2. **Init** — `fluxo init` scaffolds `.fluxo.yaml`
3. **Author** — create a manifest + `files/` templates:

<!-- tabs:start -->

#### **Go**

```
templates/
└── handler/
    ├── manifest.yaml
    └── files/
        └── handler.go.ejs.t
```

```yaml
---
to: handlers/{{ .Name | snakeCase }}.go
---
package handlers

type {{ .Name }}Handler struct {
    ID string
}

func New{{ .Name }}Handler() *{{ .Name }}Handler {
    return &{{ .Name }}Handler{}
}
```

#### **TypeScript**

```
templates/
└── react-component/
    ├── manifest.yaml
    └── files/
        └── Component.tsx.ejs.t
```

```yaml
---
to: components/{{ .Name | pascalCase }}.tsx
---
import React from 'react';

interface {{ .Name }}Props {}

export const {{ .Name }}: React.FC<{{ .Name }}Props> = () => {
  return <div>{{ .name }}</div>;
};
```

#### **Python**

```
templates/
└── fastapi-route/
    ├── manifest.yaml
    └── files/
        └── route.py.ejs.t
```

```yaml
---
to: routes/{{ .name | snakeCase }}.py
---
from fastapi import APIRouter

router = APIRouter()

@router.get("/{{ .name | kebabCase }}")
async def get_{{ .name | snakeCase }}():
    return {"message": "{{ .name }}"}
```

<!-- tabs:end -->

4. **Generate** — `fluxo generate component --name User`

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
```

### Template files (`files/*.ejs.t`)

Frontmatter defines the operation; body is the template:

```yaml
---
to: src/{{ .Name | pascalCase }}.go
---
package {{ .package }}

type {{ .Name }} struct{}
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

## Context variables

Available inside every template:

| Variable | Source |
|----------|--------|
| `{{ .cwd }}` | Current working directory |
| `{{ .actionfolder }}` | Generator action folder path |
| `{{ .name }}` | Component name (lowercase) |
| `{{ .Name }}` | Component name (PascalCase) |
| `{{ .names }}` | Pluralized lowercase |
| `{{ .Names }}` | Pluralized PascalCase |
| `{{ .attributes }}` | CLI `--key value` pairs |
| Any prompt answer | By prompt name |

## FuncMaps (template helpers)

Available via Go `text/template`:

| Function | Example |
|----------|---------|
| `{{ \| pascalCase }}` | `hello_world` → `HelloWorld` |
| `{{ \| camelCase }}` | `hello_world` → `helloWorld` |
| `{{ \| kebabCase }}` | `HelloWorld` → `hello-world` |
| `{{ \| snakeCase }}` | `HelloWorld` → `hello_world` |
| `{{ \| upper }}` | → `HELLO` |
| `{{ \| lower }}` | → `hello` |
| `{{ \| trim }}` | Strips whitespace |

## Safety

- **Transactional**: renders to `os.TempDir()`, commits atomically — no partial writes
- **Rollback**: on any failure (render error, shell error), staged files are cleaned up
- **Conflict resolution**: bulk prompt — `[y]es to all, [n]o to all, [s]elect individually, [a]bort`

## Hooks

Lifecycle hooks in `.fluxo.yaml`:

```yaml
hooks:
  pre_generate: bash scripts/validate.sh
  post_generate: node scripts/postgen.js
  timeout: 30s
```

Supported interpreters: `bash`, `sh`, `node`, `python3`, `pwsh`.

## Docs

Full documentation at [/docs](/docs), including architecture, API reference, and tutorials.
