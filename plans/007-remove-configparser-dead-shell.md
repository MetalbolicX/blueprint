# Plan 007: Remove ConfigParser dead delegation shell

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/infrastructure/config/`
> If these files changed, read the current versions before editing.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

ConfigParser.res is a 15-line file where every function is a one-liner
delegating to ConfigYaml. It exists only so ConfigStore's existing imports
don't break. It adds an unnecessary indirection layer — new contributors
must trace through ConfigStore → ConfigParser → ConfigYaml to understand
the parsing flow. Removing it simplifies the module graph.

## Current state

**File**: `src/infrastructure/config/ConfigParser.res` (15 lines):
```rescript
let parseGlobal = ConfigYaml.parseGlobal
let parse = ConfigYaml.parseConfig
let parseHookCommand = ConfigYaml.parseHookCommand
let parseHooks = ConfigYaml.parseHooks
let parseShellConfig = ConfigYaml.parseShellConfig
let mergeConfig = ConfigYaml.mergeConfig
let validateMergedConfig = ConfigYaml.validateMergedConfig
let defaultOutputDir = ConfigYaml.defaultOutputDir
let defaultTimeout = ConfigYaml.defaultTimeout
```

**File**: `src/infrastructure/config/ConfigStore.res`, lines 63 and 93 — reference
`ConfigParser.parseGlobal` and `ConfigParser.parse`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**:
- `src/infrastructure/config/ConfigParser.res` — delete
- `src/infrastructure/config/ConfigParser.resi` — delete (if exists)
- `src/infrastructure/config/ConfigStore.res` — update imports

**Out of scope**:
- Any test files referencing ConfigParser (they should already test ConfigYaml)
- Config.res facade
- ConfigYaml.res

## Steps

### Step 1: Update ConfigStore imports

In `src/infrastructure/config/ConfigStore.res`:
- Line 63: Change `ConfigParser.parseGlobal(content)` → `ConfigYaml.parseGlobal(content)`
- Line 93: Change `ConfigParser.parse(content)` → `ConfigYaml.parseConfig(content)`

**Verify**: `pnpm res:build` — should still compile (ConfigYaml is already
in the module scope).

### Step 2: Delete ConfigParser files

Delete `src/infrastructure/config/ConfigParser.res` and
`src/infrastructure/config/ConfigParser.resi` (if it exists).

**Verify**: `ls src/infrastructure/config/ConfigParser.*` returns "No such file".

### Step 3: Run tests

`pnpm res:test` — all config tests pass.

**Verify**: `grep -rn "ConfigParser" src/` returns 0 matches (excluding test files).

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `ls src/infrastructure/config/ConfigParser.*` returns "No such file"
- [ ] `grep -rn "ConfigParser" src/` returns 0 matches
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- A step's verification fails twice after a reasonable fix attempt.
- Any test file references ConfigParser and breaks.
