# Plan 021: Deduplicate isTemplateFile predicate and remove getOptString wrapper

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/infrastructure/discovery/Discovery.res src/interfaces/cli/CommandsGenerator.res src/domain/manifest/Manifest.res src/domain/template/`
> If these files changed, read the current versions before editing.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

Two identical `isTemplateFile` predicates exist in separate modules — one
private in `Discovery.res`, one public in `CommandsGenerator.res`. Both check
the same condition: filename ends with `.ejs.t` or `.tmpl`. When the definition
of "what is a template file" changes, both must be updated in lockstep or they
drift. A single source of truth eliminates this risk. Separately,
`getOptString` in `Manifest.res` is a no-op wrapper over `getString` — both
return `option<string>`. Removing it eliminates a confusing indirection.

## Current state

**File**: `src/infrastructure/discovery/Discovery.res`
- Line 4: `open Template` — opens the domain Template module
- Lines 13–15: `_isTemplateFile` (private):
```rescript
let _isTemplateFile: string => bool = filename => {
  String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl")
}
```
- Line 148: call site — `if _isTemplateFile(fname) {`

**File**: `src/interfaces/cli/CommandsGenerator.res`
- Lines 11–13: `isTemplateFile` (public):
```rescript
let isTemplateFile = (filename: string) => {
  String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl")
}
```
- Line 157: call site — `->Array.filter(isTemplateFile)`

**File**: `src/domain/manifest/Manifest.res`
- Lines 148–161: `getString` (local helper inside `parse`):
```rescript
let getString = (obj, key) => {
  switch obj {
  | JSON.Object(dict) =>
    switch dict->Dict.get(key) {
    | Some(v) =>
      switch v {
      | JSON.String(s) => Some(s)
      | _ => None
      }
    | None => None
    }
  | _ => None
  }
}
```
- Lines 164–169: `getOptString` (local helper inside `parse`) — no-op wrapper:
```rescript
let getOptString = (obj, key) => {
  switch getString(obj, key) {
  | Some(s) => Some(s)
  | None => None
  }
}
```
- Line 199: call site — `let defaultVal = getOptString(promptJson, "default")`
- Line 200: call site — `let whenVal = getOptString(promptJson, "when")`

## Where should isTemplateFile live?

The function checks whether a filename is a template file — this is a
**template-domain concept**. The natural home is `src/domain/template/Template.res`,
which already defines the `template` type and is opened by both consumers:

- `Discovery.res` line 4: `open Template`
- `CommandsGenerator.res` does not currently open Template, but as an
  `interfaces/` module it is allowed to depend on `domain/`.

**Chosen home**: `src/domain/template/Template.res` — add `isTemplateFile` as a
public function. Both `Discovery.res` and `CommandsGenerator.res` call
`Template.isTemplateFile` (or just `isTemplateFile` after `open Template`).

**Why not Infrastructure?** The function has no I/O or platform dependency — it
is a pure predicate over a filename string. Domain is the correct layer.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm build`             | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope** (the only files you should modify):
- `src/domain/template/Template.res` — add `isTemplateFile` function
- `src/infrastructure/discovery/Discovery.res` — replace `_isTemplateFile` with `Template.isTemplateFile`
- `src/interfaces/cli/CommandsGenerator.res` — replace local `isTemplateFile` with `Template.isTemplateFile`
- `src/domain/manifest/Manifest.res` — delete `getOptString`, change call sites to `getString`

**Out of scope**:
- Any test files
- Other modules that might define template-related predicates

## Git workflow

- Branch: `advisor/021-dedupe-template-predicate`
- Commit per step with conventional commit messages
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add isTemplateFile to Template.res

In `src/domain/template/Template.res`, add a public function:

```rescript
let isTemplateFile: string => bool = filename => {
  String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl")
}
```

Place it near the top of the file, after any type definitions but before other
functions. Read the file first to find the right insertion point.

**Verify**: `pnpm build` → exit 0 (adding a new function doesn't break anything)

### Step 2: Update Discovery.res to use Template.isTemplateFile

In `src/infrastructure/discovery/Discovery.res`:
1. Delete lines 13–15 (the `_isTemplateFile` definition).
2. Line 148: change `if _isTemplateFile(fname)` → `if Template.isTemplateFile(fname)`

Note: `Discovery.res` already has `open Template` at line 4, so
`isTemplateFile` is in scope directly. However, using `Template.isTemplateFile`
is explicit and preferred for clarity.

**Verify**: `pnpm build` → exit 0

### Step 3: Update CommandsGenerator.res to use Template.isTemplateFile

In `src/interfaces/cli/CommandsGenerator.res`:
1. Delete lines 11–13 (the `isTemplateFile` definition).
2. Line 157: change `->Array.filter(isTemplateFile)` → `->Array.filter(Template.isTemplateFile)`

`CommandsGenerator.res` does not currently `open Template`. Since it is in
`interfaces/` and already depends on `domain/manifest/Manifest`, adding a
`domain/template/Template` dependency is consistent with the layering.

**Verify**: `pnpm build` → exit 0

### Step 4: Remove getOptString from Manifest.res

In `src/domain/manifest/Manifest.res`:
1. Delete lines 164–169 (the `getOptString` helper):
```rescript
let getOptString = (obj, key) => {
  switch getString(obj, key) {
  | Some(s) => Some(s)
  | None => None
  }
}
```
2. Line 199: change `let defaultVal = getOptString(promptJson, "default")` → `let defaultVal = getString(promptJson, "default")`
3. Line 200: change `let whenVal = getOptString(promptJson, "when")` → `let whenVal = getString(promptJson, "when")`

**Verify**: `pnpm build` → exit 0

### Step 5: Run tests and confirm clean state

**Verify**: `pnpm res:test` → all pass

**Verify**: `grep -rn "_isTemplateFile" src/` → 0 matches

**Verify**: `grep -rn "getOptString" src/` → 0 matches

**Verify**: `grep -rn "isTemplateFile" src/` → matches only in `Template.res` (definition), `Discovery.res` (call site), and `CommandsGenerator.res` (call site)

## Test plan

No new tests required. The existing test suite covers template discovery and
manifest parsing. The refactoring is behavior-preserving.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `grep -rn "_isTemplateFile" src/` returns 0 matches
- [ ] `grep -rn "getOptString" src/` returns 0 matches
- [ ] `grep -rn "isTemplateFile" src/` returns exactly 3 files: Template.res, Discovery.res, CommandsGenerator.res
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- A step's verification fails twice after a reasonable fix attempt.
- You discover that `getOptString` is used somewhere outside `Manifest.res` (the grep in recon found only internal uses, but verify).
- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).
- `Template.res` already defines `isTemplateFile` with different semantics.

## Maintenance notes

- If a third consumer of `isTemplateFile` appears, it should import from `Template` — do not create local copies.
- The `getOptString` removal is safe because `getString` already returns `option<string>`. If a future caller needs a different return type, write a new helper with that type — don't re-introduce a no-op wrapper.
