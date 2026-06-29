# Plan 004: Wire short CLI flags -n/-o/-f

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/infrastructure/adapters/NodeJsArgParser.res`
> If the file changed since this plan was written, read the current version
> and adjust line references before editing.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

The README documents `-n <name>`, `-o <dir>`, and `-f` as valid CLI flags.
The README examples show `-n Button`, `-o src/ui`, `-f`. But the argument
parser type definition lacks the `short` field — these flags are silently
ignored at runtime. Users typing `blueprint generate react-component -n Button`
get either an error or the default name.

## Current state

**File**: `src/infrastructure/adapters/NodeJsArgParser.res`

The `parseArgOption` type (lines 1-3) only has `kind`:
```rescript
type parseArgOption = {
  @as("type") kind: string,
}
```

The options dict (lines 27-29) only sets `kind`:
```rescript
Dict.set(opts, "name", {kind: "string"})
Dict.set(opts, "output", {kind: "string"})
Dict.set(opts, "force", {kind: "boolean"})
```

Node's built-in `parseArgs` supports a `short` field on option definitions.
The README documents `-n`, `-o`, `-f`. Router.res already handles `-f` via
`args->Array.includes("-f")` as a workaround.

**Convention**: ReScript PascalCase modules, snake_case values. `@as("type")`
for JS FFI field aliases.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Bundle    | `pnpm bundle`            | exit 0              |
| Test      | `pnpm res:test`          | all pass            |

## Scope

**In scope**: `src/infrastructure/adapters/NodeJsArgParser.res`

**Out of scope**: DenoArgParser, Router.res, README, Help.res

## Steps

### Step 1: Add `short` field to parseArgOption type

Change the type to add optional `short`:
```rescript
type parseArgOption = {
  @as("type") kind: string,
  short?: string,
}
```

### Step 2: Add short aliases to option definitions

Change lines 27-29 to include short aliases:
```rescript
Dict.set(opts, "name", {kind: "string", short: "n"})
Dict.set(opts, "output", {kind: "string", short: "o"})
Dict.set(opts, "force", {kind: "boolean", short: "f"})
```

**Verify**: `pnpm res:build` — compiles without errors.

### Step 3: Build and test

```bash
pnpm build
pnpm res:test
```

### Step 4: Manual verification

Run:
```bash
node dist/main.mjs healthz
node dist/main.mjs generate react-component --help
# Verify the binary works
```

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `node dist/main.mjs generate react-component -n Button -o /tmp/test -f` parses correctly
- [ ] `node dist/main.mjs generate react-component --name Button --output /tmp/test --force` still works (long flags not broken)
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code at the locations doesn't match the excerpts.
- A step's verification fails twice after a reasonable fix attempt.
- Long flags stop working after the change.
