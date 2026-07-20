# Plan 025: Relocate PromptResolver from infrastructure to application layer

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/infrastructure/prompts/PromptResolver.res src/application/pipeline/Phase0.res src/application/engine/EnginePhases.res test/PromptResolver_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/020-purge-dead-bindings-and-helpers.md
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

`PromptResolver.res` (535 lines) lives under `src/infrastructure/prompts/` but is orchestration logic over `Ports.interactiveIO` — it evaluates EJS templates, manages prompt state, and drives interactive prompt loops. It is NOT a low-level adapter. The only production consumer is `Phase0.res:111` in `src/application/pipeline/`, which imports it directly. This creates an application→infrastructure dependency that breaks the intended hexagonal layering: application modules should depend on domain ports, not infrastructure modules. Moving `PromptResolver` to `src/application/prompts/` aligns it with its actual role and makes the dependency direction correct (application depends on application).

Plan 020 must be applied first because it removes the dead `_createReadline` and `_closeReadline` helpers from this file, reducing noise before the move.

## Current state

**File**: `src/infrastructure/prompts/PromptResolver.res` (535 lines)
- Lines 1–3: module header comment
- Lines 6–9: `resolveError` type (pure)
- Lines 15–30: `_requireOptions` (pure predicate over Manifest.prompt)
- Lines 36–42: `_hasUnsafeEjsTags` (pure)
- Lines 48–50: `_renderEval` (Ejs.render wrapper)
- Lines 54–82: `evalTemplate` (pure + Ejs)
- Lines 85–90: `_buildEvalContext` (pure)
- Lines 95–167: `_evaluateWhen`, `_evaluateDefault`, `_evaluateOptions` (pure + Ejs)
- Lines 175–220: `_validateSelectInput`, `_tokenizeMultiSelect` (pure)
- Lines 225–246: `_compilePattern`, `_matchesPattern` (pure)
- Lines 250–342: `askPrompt` (interactive — takes `~io: Ports.interactiveIO`)
- Lines 346–525: `resolve` (interactive — takes `~io: Ports.interactiveIO`)
- Lines 529–535: `_createReadline`, `_closeReadline` (dead — removed by plan 020)

**File**: `src/application/pipeline/Phase0.res`
- Line 111: the known production caller:
  ```rescript
  await PromptResolver.resolve(~io, ~prompts=ps, ~force, ~baseContext)
  ```
- Lines 121–128: pattern matches on `PromptResolver.EvaluationError`, `PromptResolver.ValidationConfigError`, `PromptResolver.MissingOptionsError`

**File**: `test/PromptResolver_test.res` (897+ lines)
- Line 1: `// PromptResolver_test — prompt resolution tests with declarative evaluation`
- Uses `PromptResolver.evalTemplate`, `PromptResolver.resolve`, `PromptResolver._validateSelectInput`, `PromptResolver._tokenizeMultiSelect`
- Error type references: `PromptResolver.EvaluationError`, `PromptResolver.MissingOptionsError`

**File**: `rescript.json`
```json
{
  "sources": [
    { "dir": "test", "subdirs": true, "type": "dev" },
    { "dir": "src", "subdirs": true }
  ],
  "package-specs": {
    "module": "esmodule",
    "in-source": true
  },
  "suffix": ".res.mjs"
}
```
No explicit path aliases — in-source compilation means module resolution is based on directory structure. Moving the file changes its path, which changes its module identity.

## Commands you will need

| Purpose   | Command                  | Expected on success       |
|-----------|--------------------------|---------------------------|
| Build     | `pnpm build`             | exit 0                    |
| Tests     | `pnpm res:test`          | all pass                  |

## Scope

**In scope**:
- `src/infrastructure/prompts/PromptResolver.res` — move to `src/application/prompts/PromptResolver.res`
- `src/application/pipeline/Phase0.res` — verify import still works (no change needed if module name is preserved)
- `test/PromptResolver_test.res` — verify tests still work (no change needed if module name is preserved)
- Stale `.res.mjs` artifacts at old path — delete after move

**Out of scope**:
- Refactoring PromptResolver's internals (that's a separate plan)
- Changes to how Phase0 uses PromptResolver
- Changes to the test file's assertions

## Steps

### Step 1: Ensure plan 020 is applied

Plan 020 removes `_createReadline` and `_closeReadline` from PromptResolver.res. Verify these are gone before proceeding.

**Verify**: `grep -n "_createReadline\|_closeReadline" src/infrastructure/prompts/PromptResolver.res` → 0 matches (plan 020 applied)

If matches are found, STOP and report — plan 020 must be applied first.

### Step 2: Grep all references to PromptResolver

Before moving, confirm the full set of references.

**Verify**: `grep -rn "PromptResolver" src/` → list all references
**Verify**: `grep -rn "PromptResolver" test/` → list all references

Expected references:
- `src/application/pipeline/Phase0.res:111,121,125,127` (import + error type matches)
- `test/PromptResolver_test.res` (many lines — test file)

If any OTHER files reference PromptResolver, add them to the in-scope list and update their imports after the move.

### Step 3: Create target directory and move file

```bash
mkdir -p src/application/prompts
mv src/infrastructure/prompts/PromptResolver.res src/application/prompts/PromptResolver.res
```

After the move, the module name remains `PromptResolver` (same filename, same directory depth from src). Since `rescript.json` has no path aliases and uses in-source compilation, the ReScript compiler resolves modules by filename across all source directories. The module name `PromptResolver` is unchanged, so all imports resolve correctly.

**Verify**: `ls src/application/prompts/PromptResolver.res` → file exists
**Verify**: `ls src/infrastructure/prompts/PromptResolver.res` → file does NOT exist

### Step 4: Delete stale .res.mjs artifacts

In-source compilation creates `.res.mjs` files alongside `.res` sources. After moving, the old `.res.mjs` artifact may still exist at the old path.

```bash
rm -f src/infrastructure/prompts/PromptResolver.res.mjs
```

Check if the old directory is now empty and remove it:
```bash
rmdir src/infrastructure/prompts 2>/dev/null || true
```

**Verify**: `ls src/infrastructure/prompts/` → directory does not exist or is empty

### Step 5: Build and verify

**Verify**: `pnpm build` → exits 0

If the build fails with a module-not-found error for `PromptResolver`, check:
1. The file was moved correctly (Step 3)
2. No stale `.res.mjs` at the old path shadows the new location
3. The `rescript.json` sources config includes `src` with subdirs (it does)

### Step 6: Run full test suite

**Verify**: `pnpm res:test` → all tests pass

### Step 7: Verify no old-path references remain

**Verify**: `grep -rn "infrastructure/prompts" src/ test/` → 0 matches

## Test plan

- No new tests required — this is a file relocation, not a behavior change.
- `test/PromptResolver_test.res` continues to work because the module name `PromptResolver` is unchanged.
- Verification: `pnpm res:test` → all pass, including all PromptResolver tests.

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `src/application/prompts/PromptResolver.res` exists
- [ ] `src/infrastructure/prompts/PromptResolver.res` does NOT exist
- [ ] `src/infrastructure/prompts/PromptResolver.res.mjs` does NOT exist
- [ ] `grep -rn "infrastructure/prompts" src/ test/` returns 0 matches
- [ ] `grep -rn "_createReadline\|_closeReadline" src/application/prompts/PromptResolver.res` returns 0 matches (plan 020 applied)
- [ ] No files outside the in-scope list are modified

## STOP conditions

- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).
- Plan 020 has not been applied (`_createReadline` or `_closeReadline` still exist in PromptResolver.res).
- `pnpm build` fails after Step 5 with a module-not-found error that persists after verifying the file exists at the new path.
- A non-file-based import mechanism is discovered (e.g., explicit module aliasing in `rescript.json` or `bsconfig.json`) that the plan didn't anticipate.
- The move causes a circular dependency (PromptResolver depends on something in infrastructure that now depends on it through application).

## Maintenance notes

- After this move, `src/infrastructure/prompts/` may be empty. If so, it can be deleted. If other prompt-related infrastructure modules are added later, they belong in `infrastructure/prompts/` (low-level adapters), not `application/prompts/` (orchestration).
- The module name `PromptResolver` is preserved — no import changes needed in any consumer. This is a property of ReScript's in-source compilation with no path aliases.
- If the project later adds `package-specs` path mappings or switches away from in-source compilation, this move may need revisiting.
