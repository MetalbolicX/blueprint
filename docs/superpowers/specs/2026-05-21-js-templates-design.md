# JS Project Templates — Design Spec

## Context

Blueprint uses Hygen-compatible EJS templates (`.ejs.t` suffix) with YAML frontmatter. We need a new generator `js-project` that scaffolds a standard JS/TS project with Node ESM or Browser (Vite) flavors. This replaces an older Hygen-only template the user maintained.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Template approach | Single generator, EJS conditionals | One `js-project` generator, 4 variant combos via prompts, avoids file duplication |
| Flavored variants | 4 combos: node-js, node-ts, browser-js, browser-ts | Covers all JS/TS × Node/Browser combinations |
| Build tool (Node-TS) | tsc only | User requested TypeScript compilation without a bundler for Node packages |
| Build tool (Browser) | Vite | Fast dev server, excellent TS support, standard choice |
| .gitignore fetch | `scripts/setup.sh` auto-run via `sh:` | Mirrors old Hygen behavior; `setup.sh` generated as template, then run |

## Template Structure

```
_templates/js-project/
  manifest.yaml
  new/
    .editorconfig.ejs.t
    opencode.json.ejs.t
    package.json.ejs.t
    .npmignore.ejs.t
    scripts/setup.sh.ejs.t
```

Action: `npx blueprint new js-project` → creates all files in current directory.

## Manifest — Prompts

| Name | Type | Description | Default |
|---|---|---|---|
| `name` | input | Project name (kebab-case) | `my-project` |
| `description` | input | Project description | `""` |
| `author` | input | Author name | `""` |
| `githubUsername` | input | GitHub username | `""` |
| `license` | input | License | `MIT` |
| `flavor` | list | Project type | `node` |
| `lang` | list | Language | `js` |

## File Designs

### `.editorconfig.ejs.t`

Static — no EJS conditionals, same content for all variants.
```yaml
---
to: .editorconfig
sh: bash scripts/setup.sh
---
# Editor configuration, see https://editorconfig.org
root = true

[*]
charset = utf-8
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true

[*.js]
quote_type = double

[*.md]
max_line_length = off
trim_trailing_whitespace = false
```

### `opencode.json.ejs.t`

Static — LSP config for TypeScript and JavaScript.
```yaml
---
to: opencode.json
---
{
  "$schema": "https://opencode.ai/config.json",
  "lsp": {
    "typescript": {
      "command": ["typescript-language-server", "--stdio"],
      "extensions": [".ts", ".tsx", ".mts", ".cts"]
    },
    "javascript": {
      "command": ["typescript-language-server", "--stdio"],
      "extensions": [".js", ".jsx", ".mjs", ".cjs"]
    }
  }
}
```

### `.npmignore.ejs.t`

Static — common Node ignores plus TS artifacts.
```yaml
---
to: .npmignore
---
node_modules/
dist/
.env
.env.*
!.env.example
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
coverage/
*.tsbuildinfo
.DS_Store
```

### `package.json.ejs.t`

Conditional on `<%= flavor %>` and `<%= lang %>`.

| Field | node-js | node-ts | browser-js | browser-ts |
|---|---|---|---|---|
| `type` | `"module"` | `"module"` | `"module"` | `"module"` |
| `scripts.dev` | — | `tsc --watch` | `vite` | `vite` |
| `scripts.build` | — | `tsc` | `vite build` | `vite build` |
| `scripts.preview` | — | — | `vite preview` | `vite preview` |
| `scripts.start` | `node src/index.js` | `node dist/index.js` | — | — |
| `engines.node` | `>=22.0.0` | `>=22.0.0` | `>=20.0.0` | `>=20.0.0` |
| `devDependencies` | — | `typescript`, `@types/node` | `vite` | `vite`, `typescript` |

### `scripts/setup.sh.ejs.t`

Fetches `.gitignore` from gitignore.io API using the `node` template.
```yaml
---
to: scripts/setup.sh
sh: chmod +x scripts/setup.sh
---
#!/usr/bin/env bash
set -euo pipefail

echo "Fetching .gitignore from gitignore.io..."
curl -sL "https://www.toptal.com/developers/gitignore/api/node" -o .gitignore
echo "Done."
```

## Shell Commands Execution

Blueprint's Phase1 renders all templates in parallel. Phase2 writes all files first, then executes `sh:` commands sequentially. This means `scripts/setup.sh` exists on disk before `sh: bash scripts/setup.sh` runs.

**Constraint**: `sh:` commands require `shell.enabled: true` in the consuming project's `.blueprint.yaml` with `curl` as an allowed tool. Without it, the script is still generated but auto-execution is silently skipped.

## Implementation Order

1. Create `_templates/js-project/manifest.yaml`
2. Create `_templates/js-project/new/.editorconfig.ejs.t`
3. Create `_templates/js-project/new/opencode.json.ejs.t`
4. Create `_templates/js-project/new/.npmignore.ejs.t`
5. Create `_templates/js-project/new/package.json.ejs.t` (most complex — EJS conditionals)
6. Create `_templates/js-project/new/scripts/setup.sh.ejs.t`
7. Write this spec to `docs/superpowers/specs/2026-05-21-js-templates-design.md`
8. Build ReScript (`pnpm res:build`)
9. Add js-project to `.blueprint.yaml` examples