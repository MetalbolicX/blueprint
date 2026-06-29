# Plan 008: Remove "(stub)" labels from generator help text

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/interfaces/cli/Help.res`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

Help.res labels three generator actions as "(stub)" — but they're fully
implemented. `CommandsGenerator.res` has complete implementations for `list`
(190 lines), `add-prompt` (73 lines), and `add-file` (168 lines). Users
see "(stub)" and assume the features don't work, suppressing adoption.

## Current state

**File**: `src/interfaces/cli/Help.res`, lines 104-106:
```rescript
Console.log("  list <name>            List prompts/templates for a generator (stub)")
Console.log("  add-prompt <name>      Add prompt to manifest.yaml (stub)")
Console.log("  add-file <name>        Add .ejs.t template file (stub)")
```

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Bundle    | `pnpm bundle`            | exit 0              |
| Verify    | `node dist/main.mjs help generator` | no "(stub)" in output |

## Scope

**In scope**: `src/interfaces/cli/Help.res`

**Out of scope**: Any other file

## Steps

### Step 1: Remove "(stub)" from all three lines

Change lines 104-106 to:
```rescript
Console.log("  list <name>            List prompts/templates for a generator")
Console.log("  add-prompt <name>      Add prompt to manifest.yaml")
Console.log("  add-file <name>        Add .ejs.t template file")
```

**Verify**: `pnpm res:build` — compiles without errors.

### Step 2: Build and verify

```bash
pnpm build
node dist/main.mjs help generator
```

The output should show the three actions without "(stub)".

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `node dist/main.mjs help generator` output contains no "(stub)" string
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code at the locations doesn't match the excerpts.
- A verification step fails twice.
