# Plan 022: Consolidate prompt-type parsing and options validation into Manifest

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/domain/manifest/Manifest.res src/interfaces/cli/CommandsGenerator.res src/infrastructure/prompts/PromptResolver.res test/Manifest_test.res`
> If these files changed, read the current versions before editing.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/020-purge-dead-bindings-and-helpers.md, plans/021-dedupe-template-predicate-and-getoptstring.md
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

`parsePromptType` exists in two places with **drifted behavior**:
- `Manifest.parsePromptType` (domain) accepts `"multi-select"` and returns
  `None` for unknown types — strict contract.
- `CommandsGenerator.parsePromptTypeFromInput` (interfaces) accepts
  `"multi-select"`, `"multi_select"`, `"multiselect"` and defaults unknown
  types to `Input` — lenient interactive contract.

This drift means the domain parser rejects aliases the CLI accepts, and the
CLI silently swallows typos the domain rejects. Consolidating into one parser
in the domain (strict) with the lenient mapping at the CLI call site makes the
contract explicit and testable. Similarly, the "select/multiselect requires
options" rule is implemented twice — once as `validate` returning
`array<validationError>` in Manifest, once as `_requireOptions` returning
`result<unit, resolveError>` in PromptResolver. A single pure predicate in
Manifest that both delegate to eliminates the duplication while preserving
each caller's error type.

## Current state

**File**: `src/domain/manifest/Manifest.res`

`parsePromptType` (lines 39–47) — strict parser, unknown → `None`:
```rescript
let parsePromptType: string => option<promptType> = s => {
  switch s {
  | "input" => Some(Input)
  | "select" => Some(Select)
  | "confirm" => Some(Confirm)
  | "multi-select" => Some(MultiSelect)
  | _ => None
  }
}
```

Options validation in `validate` (lines 317–322) — returns `array<validationError>`:
```rescript
if (p.promptType == Select || p.promptType == MultiSelect) && p.options == None {
  Js.Array.push(
    {field: "prompts.options", message: "select prompt requires options"},
    errors,
  )->ignore
}
```

**File**: `src/interfaces/cli/CommandsGenerator.res`

`parsePromptTypeFromInput` (lines 41–49) — lenient parser, unknown → `Input`:
```rescript
let parsePromptTypeFromInput = (raw: string): Manifest.promptType => {
  switch raw->String.trim->String.toLowerCase {
  | "" | "input" => Manifest.Input
  | "select" => Manifest.Select
  | "confirm" => Manifest.Confirm
  | "multi-select" | "multi_select" | "multiselect" => Manifest.MultiSelect
  | _ => Manifest.Input
  }
}
```

**File**: `src/infrastructure/prompts/PromptResolver.res`

`_requireOptions` (lines 15–30) — returns `result<unit, resolveError>`:
```rescript
let _requireOptions: Manifest.prompt => result<unit, resolveError> = prompt => {
  switch prompt.promptType {
  | Manifest.Select | Manifest.MultiSelect =>
    switch prompt.options {
    | Some(opts) if Array.length(opts) > 0 => Ok()
    | _ =>
      Error(
        MissingOptionsError({
          prompt: prompt.name,
          message: "select prompt requires options",
        }),
      )
    }
  | _ => Ok()
  }
}
```

**File**: `test/Manifest_test.res` — existing test patterns (lines 5–475):
- Uses `TestHelpers` (assert_eq, assert_true, assert_false)
- Test structure: `suite("Manifest", () => { test("name", () => { ... }) })`
- Existing tests cover: parse minimal, parse with prompts, select with options, confirm, metadata, validate missing classification, validate empty prompt name, multi-select, multi-select without options, select without options, valid manifest, when field, validate pattern, select with object options, backward compat string options, appendPromptPreservingComments, error collection, error messages, validationErrorsToString.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm build`             | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |
| Single    | `npx retest ./test/Manifest_test.res.mjs` | all pass |

## Scope

**In scope** (the only files you should modify):
- `src/domain/manifest/Manifest.res` — extend `parsePromptType` with aliases; add `requireOptions` pure predicate; update `validate` to use it
- `src/interfaces/cli/CommandsGenerator.res` — delete `parsePromptTypeFromInput`; map `Manifest.parsePromptType` result at call site
- `src/infrastructure/prompts/PromptResolver.res` — replace `_requireOptions` with `Manifest.requireOptions` call
- `test/Manifest_test.res` — add tests for aliases and strict/lenient paths

**Out of scope**:
- Changes to the `promptType` variant type itself
- Changes to how prompts are rendered or asked interactively
- Other test files

## Git workflow

- Branch: `advisor/022-consolidate-prompt-type-parsing`
- Commit per step with conventional commit messages
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Extend Manifest.parsePromptType with aliases

In `src/domain/manifest/Manifest.res`, replace `parsePromptType` (lines 39–47) with:

```rescript
let parsePromptType: string => option<promptType> = s => {
  switch s->String.trim->String.toLowerCase {
  | "input" => Some(Input)
  | "select" => Some(Select)
  | "confirm" => Some(Confirm)
  | "multi-select" | "multi_select" | "multiselect" => Some(MultiSelect)
  | _ => None
  }
}
```

Key changes:
- Normalizes input (trim + lowercase) before matching — matches CommandsGenerator's behavior
- Accepts all 3 multi-select aliases
- Still returns `None` for unknown types (strict contract preserved)

**Verify**: `pnpm build` → exit 0

**Verify**: `pnpm res:test` → all pass (existing tests still pass because they use canonical forms)

### Step 2: Add requireOptions pure predicate to Manifest.res

In `src/domain/manifest/Manifest.res`, add a new function after `parsePromptType`:

```rescript
// Pure predicate: does this prompt type require options to be meaningful?
let requireOptions: prompt => bool = prompt => {
  switch prompt.promptType {
  | Select | MultiSelect =>
    switch prompt.options {
    | Some(opts) if Array.length(opts) > 0 => false
    | _ => true
    }
  | _ => false
  }
}
```

This returns `true` when options are missing and the prompt type requires them.
Both `validate` and `PromptResolver._requireOptions` will delegate to this.

**Verify**: `pnpm build` → exit 0

### Step 3: Update Manifest.validate to use requireOptions

In `src/domain/manifest/Manifest.res`, replace lines 317–322 in the `validate` function:

Before:
```rescript
if (p.promptType == Select || p.promptType == MultiSelect) && p.options == None {
  Js.Array.push(
    {field: "prompts.options", message: "select prompt requires options"},
    errors,
  )->ignore
}
```

After:
```rescript
if Manifest.requireOptions(p) {
  Js.Array.push(
    {field: "prompts.options", message: "select prompt requires options"},
    errors,
  )->ignore
}
```

Note: since `validate` is inside `Manifest.res`, the call is just `requireOptions(p)`, not `Manifest.requireOptions(p)`.

**Verify**: `pnpm build` → exit 0

**Verify**: `npx retest ./test/Manifest_test.res.mjs` → all pass

### Step 4: Replace PromptResolver._requireOptions with Manifest.requireOptions

In `src/infrastructure/prompts/PromptResolver.res`, replace `_requireOptions` (lines 15–30) with:

```rescript
let _requireOptions: Manifest.prompt => result<unit, resolveError> = prompt => {
  if Manifest.requireOptions(prompt) {
    Error(
      MissingOptionsError({
        prompt: prompt.name,
        message: "select prompt requires options",
      }),
    )
  } else {
    Ok()
  }
}
```

The function signature stays the same — it still returns
`result<unit, resolveError>` — but the logic now delegates to the single
predicate in Manifest.

**Verify**: `pnpm build` → exit 0

### Step 5: Update CommandsGenerator to use Manifest.parsePromptType

In `src/interfaces/cli/CommandsGenerator.res`:
1. Delete `parsePromptTypeFromInput` (lines 41–49).
2. Find the call site at line 210: `let promptType = parsePromptTypeFromInput(promptTypeInput)`
3. Replace with:
```rescript
let promptType = Manifest.parsePromptType(promptTypeInput)->Option.getOr(Manifest.Input)
```

This preserves the lenient interactive behavior: unknown input defaults to
`Input`, while canonical types are parsed by the domain function. The
`Option.getOr(Manifest.Input)` mapping is explicit at the call site rather
than hidden inside a separate parser.

**Verify**: `pnpm build` → exit 0

### Step 6: Add tests for aliases and strict/lenient paths

In `test/Manifest_test.res`, add these tests inside the existing `suite("Manifest", ...)` block:

```rescript
test("parsePromptType: accepts multi_select alias", () => {
  let result = Manifest.parsePromptType("multi_select")
  assert_eq(result, Some(Manifest.MultiSelect))
})

test("parsePromptType: accepts multiselect alias", () => {
  let result = Manifest.parsePromptType("multiselect")
  assert_eq(result, Some(Manifest.MultiSelect))
})

test("parsePromptType: accepts multi-select canonical", () => {
  let result = Manifest.parsePromptType("multi-select")
  assert_eq(result, Some(Manifest.MultiSelect))
})

test("parsePromptType: normalizes case", () => {
  let result = Manifest.parsePromptType("SELECT")
  assert_eq(result, Some(Manifest.Select))
})

test("parsePromptType: returns None for unknown type", () => {
  let result = Manifest.parsePromptType("checkbox")
  assert_eq(result, None)
})

test("parsePromptType: trims whitespace", () => {
  let result = Manifest.parsePromptType("  input  ")
  assert_eq(result, Some(Manifest.Input))
})

test("requireOptions: returns true for select without options", () => {
  let prompt: Manifest.prompt = {
    name: "type",
    promptType: Manifest.Select,
    description: "Pick a type",
  }
  assert_true(Manifest.requireOptions(prompt))
})

test("requireOptions: returns false for select with options", () => {
  let prompt: Manifest.prompt = {
    name: "type",
    promptType: Manifest.Select,
    description: "Pick a type",
    options: [{label: "A", value: "a"}],
  }
  assert_false(Manifest.requireOptions(prompt))
})

test("requireOptions: returns false for input prompt", () => {
  let prompt: Manifest.prompt = {
    name: "name",
    promptType: Manifest.Input,
    description: "Name",
  }
  assert_false(Manifest.requireOptions(prompt))
})

test("requireOptions: returns true for multiselect without options", () => {
  let prompt: Manifest.prompt = {
    name: "colors",
    promptType: Manifest.MultiSelect,
    description: "Pick colors",
  }
  assert_true(Manifest.requireOptions(prompt))
})

test("parse: manifest with multi_select alias in YAML", () => {
  let yaml = "name: test\nclassification: test\nprompts:\n  - name: colors\n    type: multi_select\n    options:\n      - red\n      - blue\n"
  let result = Manifest.parse(yaml)
  switch result {
  | Ok(m) => switch m.prompts {
    | Some(prompts) => switch prompts[0] {
      | Some(p) => assert_eq(p.promptType, Manifest.MultiSelect)
      | None => assert_false(true)
      }
    | None => assert_false(true)
    }
  | Error(_) => assert_false(true)
  }
})

test("parse: manifest with multiselect alias in YAML", () => {
  let yaml = "name: test\nclassification: test\nprompts:\n  - name: colors\n    type: multiselect\n    options:\n      - red\n      - blue\n"
  let result = Manifest.parse(yaml)
  switch result {
  | Ok(m) => switch m.prompts {
    | Some(prompts) => switch prompts[0] {
      | Some(p) => assert_eq(p.promptType, Manifest.MultiSelect)
      | None => assert_false(true)
      }
    | None => assert_false(true)
    }
  | Error(_) => assert_false(true)
  }
})

test("validate: unknown type parsed as None defaults to Input in parse", () => {
  // parsePromptType returns None for unknown, but parse uses Option.getOr(Input)
  // So a manifest with type: "checkbox" should parse as Input
  let yaml = "name: test\nclassification: test\nprompts:\n  - name: x\n    type: checkbox\n    description: test\n"
  let result = Manifest.parse(yaml)
  switch result {
  | Ok(m) => switch m.prompts {
    | Some(prompts) => switch prompts[0] {
      | Some(p) => assert_eq(p.promptType, Manifest.Input)
      | None => assert_false(true)
      }
    | None => assert_false(true)
    }
  | Error(_) => assert_false(true)
  }
})
```

**Verify**: `npx retest ./test/Manifest_test.res.mjs` → all pass, including N new tests

**Verify**: `pnpm res:test` → all pass

### Step 7: Final verification — grep for removed identifiers

**Verify**: `grep -rn "parsePromptTypeFromInput" src/` → 0 matches

**Verify**: `grep -rn "getOptString" src/` → 0 matches (may already be 0 from plan 021)

**Verify**: `pnpm build` → exit 0

## Test plan

- **New tests** (in `test/Manifest_test.res`):
  - `parsePromptType` accepts all 3 multi-select aliases
  - `parsePromptType` normalizes case and trims whitespace
  - `parsePromptType` returns `None` for unknown types
  - `requireOptions` returns correct bool for select/multiselect/input with and without options
  - `parse` handles `multi_select` and `multiselect` aliases in YAML
  - `parse` defaults unknown type to `Input` (lenient path at parse level)
- **Existing tests** that validate the change:
  - All existing Manifest_test tests pass (behavior preserved)
  - PromptResolver tests (if any) pass — `_requireOptions` now delegates to Manifest

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `npx retest ./test/Manifest_test.res.mjs` exits 0 with all new alias/requireOptions tests passing
- [ ] `grep -rn "parsePromptTypeFromInput" src/` returns 0 matches
- [ ] `grep -rn "getOptString" src/` returns 0 matches
- [ ] `grep -rn "requireOptions" src/domain/manifest/Manifest.res` returns at least 1 match (the definition)
- [ ] `grep -rn "requireOptions" src/infrastructure/prompts/PromptResolver.res` returns at least 1 match (the call site)
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- A step's verification fails twice after a reasonable fix attempt.
- The drift check shows `Manifest.parsePromptType` or `CommandsGenerator.parsePromptTypeFromInput` has changed since the excerpts were captured.
- The "select/multiselect requires options" rule in `Manifest.validate` or `PromptResolver._requireOptions` has changed since the excerpts were captured.
- You discover that `parsePromptTypeFromInput` is referenced somewhere other than its definition and its single call site at line 210.
- A test asserts behavior that contradicts the plan (e.g., unknown type should NOT default to Input).

## Maintenance notes

- The domain `parsePromptType` is strict (unknown → `None`). The CLI maps `None → Input` at its call site. This boundary is intentional: domain code should never silently guess; UI code can provide defaults.
- If new prompt types are added, both `parsePromptType` and the `requireOptions` predicate must be updated together.
- The `_requireOptions` function in PromptResolver now delegates to `Manifest.requireOptions`. Its error type (`resolveError`) is preserved — the Manifest function returns a pure `bool`, and PromptResolver wraps it in its own error variant.
- Plans 020 and 021 should be applied first. Plan 020 removes `parseError` from Manifest.res (shifts line numbers). Plan 021 removes `getOptString` from Manifest.res. This plan assumes both are already applied — if not, line numbers in "Current state" will differ.
