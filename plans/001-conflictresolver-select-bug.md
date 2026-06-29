# Plan 001: Fix ConflictResolver Select mode overwrite bug

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/domain/conflicts/ConflictResolver.res`
> If the file changed since this plan was written, read the current version
> and adjust the line references before proceeding.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

The ConflictResolver's "select" (per-file) mode is completely broken: every
user response, including "y" (yes, overwrite), maps to `overwrite=false`.
The file is silently skipped. This means users who pick "s" at the conflict
prompt and then type "y" for a specific file will never get that file
overwritten — a full UX bug in the only interactive per-file resolution path.

## Current state

**File**: `src/domain/conflicts/ConflictResolver.res`

The `resolution` type has 4 variants: `YesAll | NoAll | Select | Abort`.
The `parseChoice` function maps `"y"` and `"yes"` to `Some(YesAll)`.

In the `Select` branch (line 87):
```rescript
| Select =>
    let decisions: array<conflictDecision> = []
    let rec loop = (idx: int, conflicts: array<fileConflict>) => {
      if idx >= Array.length(conflicts) {
        Promise.resolve(Ok(decisions))
      } else {
        switch conflicts[idx] {
        | Some(c) =>
          io.ask(
            "Overwrite " ++ c.targetPath ++ "? [y]es / [n]o: ",
          )->Promise.then(answer => {
            let overwrite = switch parseChoice(answer) {
            | Some(YesAll) | Some(NoAll) | None => false
            | _ => true
            }
```

`parseChoice("y")` returns `Some(YesAll)` which matches the first arm → `false`.
The per-file "yes" answer is impossible to express because `parseChoice` has
no per-file "yes" variant — it treats `"y"` as bulk `YesAll`.

**Convention**: ReScript uses PascalCase modules, snake_case values. Test
files use `suite("name", () => { test("desc", () => {...}) })` from rescript-test.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**:
- `src/domain/conflicts/ConflictResolver.res` — fix the Select branch
- `test/ConflictResolver_test.res` — add test for per-file yes/no

**Out of scope**:
- Any changes to other modules
- Changing the bulk-resolution prompt or flow

## Steps

### Step 1: Add `Yes` variant to `resolution`

Add `Yes` to the `resolution` type so there's a per-file "yes overwrite"
distinct from `YesAll` (bulk overwrite all).

After line 5 (`| YesAll`), add:
```rescript
  | Yes // overwrite this file
```

### Step 2: Update `parseChoice` to return `Yes` for per-file answers

Change line 26 from:
```rescript
| "y" | "yes" | "a" | "all" => Some(YesAll)
```
to:
```rescript
| "y" | "yes" => Some(Yes)
| "a" | "all" => Some(YesAll)
```

This way `parseChoice` returns `Yes` when the user types "y" for a single file,
and `YesAll` only when they type "a" or "all".

### Step 3: Fix the Select branch overwrite logic

In the `Select` branch (line 99), replace:
```rescript
let overwrite = switch parseChoice(answer) {
| Some(YesAll) | Some(NoAll) | None => false
| _ => true
}
```
with:
```rescript
let overwrite = switch parseChoice(answer) {
| Some(Yes) => true
| _ => false
}
```

This means only `Yes` (user typed "y") maps to overwrite=true. Everything
else (NoAll, YesAll, None, Abort) maps to false, which is the correct
per-file behavior — if the user wanted to overwrite all they'd say "a" at
the bulk prompt, not go into select mode.

**Verify**: `pnpm res:build` — should compile without errors.

### Step 4: Add test for Select mode yes/no

In `test/ConflictResolver_test.res`, add tests that assert:
- `parseChoice("y")` returns `Some(Yes)`
- `parseChoice("yes")` returns `Some(Yes)`
- `parseChoice("n")` returns `Some(NoAll)` (unchanged)
- `parseChoice("a")` returns `Some(YesAll)` (unchanged)

Model after the existing test patterns in the file.

**Verify**: `pnpm res:test` — all tests pass, including the new ones.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; new tests for Select mode yes/no exist and pass
- [ ] Running generator with `--force=false` and a conflicting file, selecting
      "s" then "y" on one file — that file gets overwritten
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code at `src/domain/conflicts/ConflictResolver.res` doesn't match the
  excerpts above (read the current file and adjust line numbers before
  editing).
- A step's verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file.

## Maintenance notes

The `parseChoice` function now returns three meaningful values for "yes":
`Yes` (per-file), `YesAll` (bulk). The `Abort` variant is never returned by
`parseChoice` because there's no per-file abort key — that's by design.
