# Plan 006: Extract duplicated h-helpers dict construction

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/infrastructure/rendering/Renderer.res src/application/pipeline/TemplateRenderer.res src/domain/template/FuncMap.res`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

The identical 11-line dict construction for `h.*` helpers (pascalCase, camelCase,
kebabCase, snakeCase, upper, lower, trim, title) is duplicated in both
`Renderer.res` and `TemplateRenderer.res`. If one adds a helper and the other
doesn't, the behavior diverges silently. Extracting to `FuncMap.res` ensures
a single source of truth.

## Current state

**File**: `src/infrastructure/rendering/Renderer.res`, lines 56-66:
```rescript
let hObj = Dict.make()
Dict.set(hObj, "pascalCase", helpers.pascalCase->Obj.magic)
Dict.set(hObj, "camelCase", helpers.camelCase->Obj.magic)
Dict.set(hObj, "kebabCase", helpers.kebabCase->Obj.magic)
Dict.set(hObj, "snakeCase", helpers.snakeCase->Obj.magic)
Dict.set(hObj, "upper", helpers.upper->Obj.magic)
Dict.set(hObj, "lower", helpers.lower->Obj.magic)
Dict.set(hObj, "trim", helpers.trim->Obj.magic)
Dict.set(hObj, "title", helpers.title->Obj.magic)
Dict.set(data, "h", hObj->Obj.magic)
```

**File**: `src/application/pipeline/TemplateRenderer.res`, lines 40-51:
```rescript
let hObj = Dict.make()
Dict.set(hObj, "pascalCase", helpers.pascalCase->Obj.magic)
Dict.set(hObj, "camelCase", helpers.camelCase->Obj.magic)
Dict.set(hObj, "kebabCase", helpers.kebabCase->Obj.magic)
Dict.set(hObj, "snakeCase", helpers.snakeCase->Obj.magic)
Dict.set(hObj, "upper", helpers.upper->Obj.magic)
Dict.set(hObj, "lower", helpers.lower->Obj.magic)
Dict.set(hObj, "trim", helpers.trim->Obj.magic)
Dict.set(hObj, "title", helpers.title->Obj.magic)
Dict.set(data, "h", hObj->Obj.magic)
```

**File**: `src/domain/template/FuncMap.res` — already has `makeHelpers()` returning a typed `helpers` record. This is where the shared function should live.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**:
- `src/domain/template/FuncMap.res`
- `src/infrastructure/rendering/Renderer.res`
- `src/application/pipeline/TemplateRenderer.res`

**Out of scope**:
- Any changes to the `helpers` type or `makeHelpers` signature
- Any other file

## Steps

### Step 1: Add `makeHelpersDict` to FuncMap.res

Add this function to `src/domain/template/FuncMap.res`:
```rescript
let makeHelpersDict: unit => dict<'a> = () => {
  let helpers = makeHelpers()
  let hObj = Dict.make()
  Dict.set(hObj, "pascalCase", helpers.pascalCase->Obj.magic)
  Dict.set(hObj, "camelCase", helpers.camelCase->Obj.magic)
  Dict.set(hObj, "kebabCase", helpers.kebabCase->Obj.magic)
  Dict.set(hObj, "snakeCase", helpers.snakeCase->Obj.magic)
  Dict.set(hObj, "upper", helpers.upper->Obj.magic)
  Dict.set(hObj, "lower", helpers.lower->Obj.magic)
  Dict.set(hObj, "trim", helpers.trim->Obj.magic)
  Dict.set(hObj, "title", helpers.title->Obj.magic)
  hObj
}
```

**Verify**: `pnpm res:build` — compiles without errors.

### Step 2: Replace in Renderer.res

In `src/infrastructure/rendering/Renderer.res`, replace lines 56-66 with:
```rescript
Dict.set(data, "h", FuncMap.makeHelpersDict()->Obj.magic)
```

Remove the `let hObj = Dict.make()` + 8 `Dict.set` lines.

**Verify**: `pnpm res:build` — compiles without errors.

### Step 3: Replace in TemplateRenderer.res

In `src/application/pipeline/TemplateRenderer.res`, replace lines 40-51 with:
```rescript
Dict.set(data, "h", FuncMap.makeHelpersDict()->Obj.magic)
```

Remove the 9 lines between the comment and `Dict.set(data, "h", ...)`.

Note: The `let helpers = makeHelpers()` call on line 41 may no longer be needed
if `helpers` is only used for the dict. Remove it too if so.

**Verify**: `pnpm res:build` — compiles without errors.

### Step 4: Run tests

`pnpm res:test` — all tests pass, including EJS rendering and template path tests.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `grep -n "hObj" src/infrastructure/rendering/Renderer.res src/application/pipeline/TemplateRenderer.res` returns 0 matches
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- A step's verification fails twice after a reasonable fix attempt.
- The fix breaks EJS rendering of templates that use `h.*` helpers.

## Maintenance notes

When a new helper is added to `makeHelpers`, the corresponding `Dict.set` must
also be added to `makeHelpersDict`. This is the single point of update now.
