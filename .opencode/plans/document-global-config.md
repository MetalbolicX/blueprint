# Plan: Document global configuration

## Problem

The global config (`~/.config/blueprint/config.yaml`) exists in the codebase (`Config.res:188-189`) and is loaded by the engine, but is completely absent from all user-facing docs. Users have no way to know about template search paths, `--force` defaults, dry-run mode, or default attributes.

## Changes

### 1. `docs/api-reference.md` — New "Global configuration" section

Insert after the `.blueprint.yaml` section (after line 157, before "Exit codes"):

```markdown
## Global configuration

`~/.config/blueprint/config.yaml` applies to all projects. Project-level `.blueprint.yaml` values override global ones where applicable.

```yaml
# Template search paths (discovered in addition to _templates/)
templates:
  - ~/my-org/shared-templates

# Allow legacy shell execution in config (default: false)
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
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `templates` | array | `[]` | Additional template search paths |
| `allow_dangerous_commands` | bool | `false` | Allow legacy shell execution |
| `force_overwrite` | bool | `false` | Skip prompts, overwrite existing files |
| `dry_run` | bool | `false` | Render templates without writing output |
| `timeout` | int | `5` | Hook execution timeout in seconds |
| `default_attributes` | dict | `{}` | Default CLI attributes for all generations |
```

### 2. `docs/quick-reference.md` — Add global config block

Insert after `.blueprint.yaml` section (after line 118, before "Phase flow"):

```markdown
## ~/.config/blueprint/config.yaml

```yaml
templates: [<path>]
allow_dangerous_commands: true|false   # default false
force_overwrite: true|false            # default false
dry_run: true|false                    # default false
timeout: <int>                         # default 5
default_attributes: {k: v}
```
```

## Verification

After changes:
- `grep -r "global" docs/*.md` should show hits in api-reference.md and quick-reference.md
- Both global config file path (`~/.config/blueprint/config.yaml`) and fields should be documented
