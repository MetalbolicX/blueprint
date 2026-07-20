# Plan 017: Preserve Phase2/rollback error detail through the engine boundary

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/application/pipeline/Commit.res src/application/pipeline/Commit.resi src/application/engine/EngineOrchestrator.res src/interfaces/cli/Commands.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

When Phase2 rollback fails, two independent layers discard the underlying error detail. First, `Commit.rollbackOutput` catch-alls return only the file path — the user never learns *why* the restore failed (permission denied, disk full, etc.). Second, `EngineOrchestrator.run` collapses the rich `phase2Error` type (which carries `partialCommit`, `catastrophic`, and `failedRollbackFiles` fields) to a flat `e.message` string, so `Commands.res` cannot distinguish a catastrophic rollback failure from a benign file-exists conflict. Rollback is the safety net — losing its diagnostics defeats it.

## Current state

- `src/application/pipeline/Commit.res` — owns `phase2Error` and `backupEntry` types, the `rollbackOutput` function, and the `commitFiles` function:
  ```rescript
  // Commit.res:11-16 — canonical phase2Error type
  type phase2Error = {
    message: string,
    partialCommit?: array<string>,
    catastrophic?: bool,
    failedRollbackFiles?: array<string>,
  }
  ```
  ```rescript
  // Commit.res:140-141 — rollbackOutput cp catch-all (discards error)
  | _ => Error(outputPath)
  ```
  ```rescript
  // Commit.res:148-149 — rollbackOutput rm catch-all (discards error)
  | _ => Error(outputPath)
  ```
  ```rescript
  // Commit.res:156 — rollbackOutput collects failed paths
  let failedPaths = results->Array.filterMap(r => switch r { | Error(p) => Some(p) | Ok(_) => None })
  ```
  The return type is `promise<result<unit, array<string>>>` — the error channel carries only path strings.

- `src/application/pipeline/Commit.resi:6` — interface exposes the type:
  ```rescript
  type phase2Error = {
    message: string,
    partialCommit?: array<string>,
    catastrophic?: bool,
    failedRollbackFiles?: array<string>,
  }
  ```

- `src/application/engine/EngineOrchestrator.res:100-103` — collapses phase2Error to flat string:
  ```rescript
  switch phase2Result {
  | Error(e) =>
    io.close()
    Error(e.message)
  ```
  The return type is `promise<result<generateResult, string>>` — the rich error fields are lost.

- `src/application/engine/Engine.res:3` — re-exports:
  ```rescript
  let run = EngineOrchestrator.run
  ```

- `src/interfaces/cli/Commands.res:202-205` — caller can only see the flat string:
  ```rescript
  switch result {
  | Error(e) => {
      Console.error("Error: " ++ e)
      deps.process.exit(1)
    }
  ```

- `src/application/pipeline/Phase2.res:78-111` — Phase2.run calls `Commit.rollbackOutput` and constructs `phase2Error` with the fields from the Commit type. The `failedRollbackFiles` field is populated from `rollbackOutput`'s `array<string>` error channel. This is the upstream consumer.

- Repo conventions: Conventional commits, PascalCase modules, snake_case values. Error handling uses `result` types. The `Ports` module defines filesystem/shell/process abstractions.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm build`             | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/Commit.res` — capture JsExn messages in rollbackOutput catch-alls; change error channel to carry structured data
- `src/application/pipeline/Commit.resi` — update rollbackOutput signature
- `src/application/engine/EngineOrchestrator.res` — change error channel from `string` to carry phase2Error or a wrapper
- `src/interfaces/cli/Commands.res` — pattern-match on the richer error type and format distinct user-facing messages

**Out of scope**:
- `src/application/pipeline/Phase2.res` — already constructs phase2Error correctly; no change needed
- `src/application/engine/Engine.res` — pure re-export, no logic change needed
- Any other callers of EngineOrchestrator.run — grep confirms only Commands.res calls it (via Engine.run)

## Git workflow

- Branch: `advisor/017-preserve-phase2-error-detail`
- Commit per step or per logical unit; message style: conventional commits, e.g. `fix(commit): capture error message in rollback catch-alls`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Capture error messages in Commit.rollbackOutput catch-alls

In `src/application/pipeline/Commit.res`, change the `rollbackOutput` function's error channel from `array<string>` (paths only) to `array<{path: string, reason: string}>` so each failed path carries the underlying error message.

Replace the two catch-all blocks:

```rescript
// Commit.res:140-141 — BEFORE:
| _ => Error(outputPath)

// AFTER:
| JsExn(obj) =>
  let msg = switch JsExn.message(obj) {
  | Some(m) => m
  | None => "unknown error"
  }
  Error({path: outputPath, reason: msg})
| _ => Error({path: outputPath, reason: "unknown error"})
```

```rescript
// Commit.res:148-149 — BEFORE:
| _ => Error(outputPath)

// AFTER:
| JsExn(obj) =>
  let msg = switch JsExn.message(obj) {
  | Some(m) => m
  | None => "unknown error"
  }
  Error({path: outputPath, reason: msg})
| _ => Error({path: outputPath, reason: "unknown error"})
```

Define a local type at the top of the rollbackOutput function or near the function signature:
```rescript
type rollbackFailure = {
  path: string,
  reason: string,
}
```

Update the failedPaths collection (line 156) to extract `path` from the structured type:
```rescript
let failedPaths = results->Array.filterMap(r => switch r { | Error(f) => Some(f.path) | Ok(_) => None })
```

Update the `failedRollbackFiles` field population in Phase2.res if needed (Phase2.res:98 passes `failedRollbackFiles` from `rollbackOutput`'s error — since we changed the error shape, verify Phase2 still compiles; it should since `failedRollbackFiles` is `array<string>` and we still extract `.path`).

**Verify**: `pnpm build` → exit 0

### Step 2: Update Commit.resi for rollbackOutput signature

In `src/application/pipeline/Commit.resi`, update the `rollbackOutput` type signature to match the new error channel. The return type changes from `promise<result<unit, array<string>>>` to `promise<result<unit, array<Commit.rollbackFailure>>>` (or use the inline record type if `rollbackFailure` is defined in Commit.res and exported via .resi).

**Verify**: `pnpm build` → exit 0

### Step 3: Change EngineOrchestrator.run error channel to carry phase2Error

In `src/application/engine/EngineOrchestrator.res`, change the return type from `promise<result<generateResult, string>>` to `promise<result<generateResult, Commit.phase2Error>>`.

At line 101-103, replace:
```rescript
| Error(e) =>
  io.close()
  Error(e.message)
```

With:
```rescript
| Error(e) =>
  io.close()
  Error(e)
```

This preserves the full `phase2Error` with `partialCommit`, `catastrophic`, and `failedRollbackFiles` fields.

**Verify**: `pnpm build` → exit 0

### Step 4: Update Commands.res to pattern-match on phase2Error

In `src/interfaces/cli/Commands.res`, at lines 202-205, replace the flat string handler with structured matching:

```rescript
// BEFORE:
switch result {
| Error(e) => {
    Console.error("Error: " ++ e)
    deps.process.exit(1)
  }

// AFTER:
switch result {
| Error(e) => {
    Console.error("Error: " ++ e.message)
    switch e.partialCommit {
    | Some(files) if files->Array.length > 0 =>
      Console.error("Partially committed files: " ++ files->Array.join(", "))
    | _ => ()
    }
    switch e.catastrophic {
    | Some(true) =>
      switch e.failedRollbackFiles {
      | Some(failed) if failed->Array.length > 0 =>
        Console.error("WARNING: Could not rollback these files: " ++ failed->Array.join(", "))
      | _ => ()
      }
      Console.error("Catastrophic failure — output directory may be in an inconsistent state")
    | _ => ()
    }
    deps.process.exit(1)
  }
```

**Verify**: `pnpm build` → exit 0

### Step 5: Run full test suite

**Verify**: `pnpm res:test` → all tests pass (no regressions)

## Test plan

- No new test file needed — the changes are structural (error type propagation) and the existing test suite covers the pipeline end-to-end.
- Verify that existing `test/Phase2_test.res` and `test/ShellExecutor_test.res` still pass (they exercise the pipeline error paths).
- Verification: `pnpm res:test` → all pass

## Done criteria

- Machine-checkable. ALL must hold:
- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `grep -rn "| _ => Error(outputPath)" src/application/pipeline/Commit.res` returns no matches (catch-alls now capture JsExn)
- [ ] `grep -rn "Error(e.message)" src/application/engine/EngineOrchestrator.res` returns no matches (no more flattening)
- [ ] No files outside the in-scope list are modified (`git status`)

## STOP conditions

- The code at `Commit.res:140-141` or `:148-149` doesn't match the described catch-all patterns
- The code at `EngineOrchestrator.res:101-103` doesn't match the described `Error(e.message)` pattern
- `phase2Error` type shape differs from what's quoted in Current state
- Callers of `EngineOrchestrator.run` beyond `Commands.res` exist (grep confirms only Commands.res via Engine.run)
- `pnpm build` fails after Step 1 and the fix isn't obvious after one attempt

## Maintenance notes

- The `rollbackFailure` type is local to Commit.res — if other modules need it in the future, promote it to a shared types module.
- The `catastrophic` field in phase2Error is an `option<bool>` — future callers should pattern-match on `Some(true)` explicitly.
- If Phase2.res changes how it constructs phase2Error, verify the `failedRollbackFiles` field still receives the `path` strings from the new structured error.
