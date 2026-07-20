# Plan 027: Refactor EngineOrchestrator nested phase chain to pipeline accumulator

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/application/engine/EngineOrchestrator.res src/application/engine/EnginePhases.res src/application/engine/EngineLifecycle.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/017-preserve-phase2-error-detail.md
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

`EngineOrchestrator.run` is ~116 lines of 6-level nested `switch await` chaining Phase0 → Phase1 → Phase2 with inline error handling at each level. The deep nesting makes it hard to follow the control flow, hard to see where `io.close()` is called on each path, and hard to verify that cleanup happens correctly on every error branch. Refactoring to an accumulator/early-return style collapses the nesting to ~2 levels while preserving EXACT current behavior. This is a maintainability refactor — NO behavior change.

Plan 017 must be applied first because it changes the error channel from `string` to `Commit.phase2Error`. This plan builds on that new shape.

## Current state

**File**: `src/application/engine/EngineOrchestrator.res` (128 lines)

`run` function (lines 5–128) — the current nested structure:

```rescript
let run: (...) => promise<result<generateResult, string>> = async (...) => {
  let {fs, path, process: proc, shell, interactiveIO: io} = deps

  Fetcher.clearCache()                                           // L24
  await EngineLifecycle.cleanupOrphans(~outputDir, ~fs, ~path)  // L25

  let context = await EngineContext.buildInitialContext(...)      // L27-32

  switch await EngineHooks.runPreHook(...) {                     // L34 — LEVEL 1
  | Error(e) =>
    io.close()                                                   // L36
    Error(e)                                                     // L37
  | Ok() =>
    switch await EnginePhases.runPhase0(...) {                   // L39 — LEVEL 2
    | Error(e) => Error(e)                                       // L40
    | Ok((p0, decisions)) =>
      io.close()                                                 // L42

      let mergedContext = EngineContext.buildMergedContext(...)   // L44-49
      let shellConfig = ...                                      // L51

      switch await EnginePhases.runPhase1(...) {                 // L53 — LEVEL 3
      | Error(e) => Error(e)                                     // L64
      | Ok(p1) =>
        let stagingDirRef = ref(Some(p1.stagingDir))             // L66
        EngineLifecycle.registerSignalHandlers(...)              // L67
        let isDryRun = ...                                       // L68

        if isDryRun {                                            // L70 — LEVEL 4
          // dry run path...
          Ok(result)                                             // L83
        } else {
          let phase2Result = await Phase2.run(...)               // L85 — LEVEL 5

          stagingDirRef.contents = None                          // L97
          proc.removeSignalListeners()                           // L98

          switch phase2Result {                                  // L100 — LEVEL 6
          | Error(e) =>
            io.close()                                           // L102
            Error(e.message)                                     // L103
          | Ok(p2) =>
            // build result...
            let finalResult = await EngineHooks.runPostHook(...) // L112
            io.close()                                           // L121
            finalResult                                          // L122
          }
        }
      }
    }
  }
}
```

Key behavior to preserve:
- `Fetcher.clearCache()` runs unconditionally at the start
- `EngineLifecycle.cleanupOrphans` runs unconditionally after cache clear
- `EngineHooks.runPreHook` — on error, `io.close()` then return error
- `EnginePhases.runPhase0` — on error, return error (NO `io.close()` here — it's called in `EnginePhases.runPhase0` itself at line 16)
- `io.close()` is called after Phase0 succeeds (line 42), then Phase1 runs
- `EnginePhases.runPhase1` — on error, `io.close()` is called inside it (line 62)
- Dry run path — `stagingDirRef = None`, remove signal listeners, rollback, return Ok
- Phase2 — on error, `io.close()` then return error; on success, run post-hook, `io.close()`, return result

**File**: `src/application/engine/EnginePhases.res` (65 lines)

`runPhase0` (lines 4–35):
```rescript
let runPhase0: (...) => promise<result<(Phase0.phase0Result, array<ConflictResolver.conflictDecision>), string>> = async (...) => {
  let phase0Result = await Phase0.run(...)
  switch phase0Result {
  | Error(e) =>
    io.close()     // L17 — closes io on Phase0 error
    Error(e)
  | Ok(p0) =>
    let conflictResult = await ConflictResolver.resolveConflicts(...)
    switch conflictResult {
    | Error(e) =>
      io.close()   // L30 — closes io on conflict error
      Error(e)
    | Ok(decisions) => Ok((p0, decisions))
    }
  }
}
```

`runPhase1` (lines 37–65):
```rescript
let runPhase1: (...) => promise<result<Phase1.phase1Result, string>> = async (...) => {
  let phase1Result = await Phase1.run(...)
  switch phase1Result {
  | Error(e) =>
    io.close()     // L62 — closes io on Phase1 error
    Error(e.message)
  | Ok(p1) => Ok(p1)
  }
}
```

**File**: `src/application/engine/EngineLifecycle.res` (109 lines)
- `cleanupOrphans` (lines 25–79) — cleans up stale staging dirs and backup dirs
- `registerSignalHandlers` (lines 81–109) — registers SIGINT/SIGTERM handlers

**File**: `src/application/engine/Engine.res`
- Line 3: `let run = EngineOrchestrator.run` — pure re-export

## Commands you will need

| Purpose   | Command                  | Expected on success       |
|-----------|--------------------------|---------------------------|
| Build     | `pnpm build`             | exit 0                    |
| Tests     | `pnpm res:test`          | all pass                  |
| Smoke     | `node dist/main.mjs generate react-app --output /tmp/smoke-test --force` | generates files |

## Scope

**In scope**:
- `src/application/engine/EngineOrchestrator.res` — refactor `run` to accumulator/early-return style

**Out of scope**:
- `src/application/engine/EnginePhases.res` — the `io.close()` calls inside Phase0/Phase1 are correct and stay
- `src/application/engine/EngineLifecycle.res` — no changes needed
- `src/application/engine/Engine.res` — pure re-export, no change
- Behavior changes — this is purely structural

## Steps

### Step 1: Ensure plan 017 is applied

Plan 017 changes the error channel from `string` to `Commit.phase2Error`. Verify the new shape.

**Verify**: `grep -n "phase2Error" src/application/engine/EngineOrchestrator.res` → at least 1 match (the Error(e) branch now carries phase2Error)

If the error channel is still `string`, STOP and report — plan 017 must be applied first.

### Step 2: Rewrite EngineOrchestrator.run with accumulator style

Replace the entire `run` function body. The key structural change: instead of nesting `switch await` 6 levels deep, use a sequence of `await` + early-return pattern:

```rescript
let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
  ~config=?,
  ~deps,
) => {
  let {fs, path, process: proc, shell, interactiveIO: io} = deps

  // Phase 0: setup (unconditional)
  Fetcher.clearCache()
  await EngineLifecycle.cleanupOrphans(~outputDir, ~fs, ~path)

  let context = await EngineContext.buildInitialContext(
    ~fs,
    ~generatorPath=generator.name,
    ~name,
    ~cliAttributes,
  )

  // Pre-hook
  switch await EngineHooks.runPreHook(~config, ~projectRoot=context.cwd, ~shell, ~process=proc, ~path, ~fs) {
  | Error(e) =>
    io.close()
    return Error(e)
  | Ok() => ()
  }

  // Phase 0: prompt resolution + conflict detection
  // NOTE: io.close() is called inside EnginePhases.runPhase0 on error or after success
  let (p0, decisions) = switch await EnginePhases.runPhase0(~io, ~generator, ~context, ~outputDir, ~force, ~fs, ~path) {
  | Error(e) => return Error(e)
  | Ok(result) => result
  }

  io.close()

  // Build merged context
  let mergedContext = EngineContext.buildMergedContext(
    ~initialContext=context,
    ~name,
    ~cliAttributes,
    ~promptAnswers=p0.resolvedAttributes,
  )

  let shellConfig = config->Option.flatMap(c => c.shell)

  // Phase 1: render to staging
  // NOTE: io.close() is called inside EnginePhases.runPhase1 on error
  let p1 = switch await EnginePhases.runPhase1(
    ~io,
    ~templates=generator.templates,
    ~mergedContext,
    ~outputDir,
    ~conflictDecisions=Some(decisions),
    ~shellConfig,
    ~fs,
    ~path,
    ~process=proc,
  ) {
  | Error(e) => return Error(e)
  | Ok(p1) => p1
  }

  // Signal handler setup
  let stagingDirRef = ref(Some(p1.stagingDir))
  EngineLifecycle.registerSignalHandlers(~process=proc, ~stagingDirRef, ~fs)
  let isDryRun = config->Option.flatMap(c => c.dryRun)->Option.getOr(false)

  // Dry run path
  if isDryRun {
    stagingDirRef.contents = None
    proc.removeSignalListeners()
    Console.log(
      "Dry run — would generate " ++ Int.toString(p1.renderedFiles->Array.length) ++ " file(s)",
    )
    let _ = await Commit.rollback(p1.stagingDir, ~fs)
    return Ok({
      filesCreated: p1.renderedFiles->Array.length,
      filesInjected: 0,
      commandsExecuted: 0,
      classification: generator.name,
    })
  }

  // Phase 2: commit to output
  let phase2Result = await Phase2.run(
    ~stagingDir=p1.stagingDir,
    ~outputDir,
    ~renderedFiles=p1.renderedFiles,
    ~shellCommands=p1.shellCommands,
    ~shellConfig,
    ~fs,
    ~path,
    ~process=proc,
    ~shell,
  )

  stagingDirRef.contents = None
  proc.removeSignalListeners()

  switch phase2Result {
  | Error(e) =>
    io.close()
    return Error(e.message)
  | Ok(p2) =>
    let result: generateResult = {
      filesCreated: p2.filesCreated,
      filesInjected: p2.filesInjected,
      commandsExecuted: p2.commandsExecuted,
      classification: generator.name,
      shellErrors: ?p2.shellErrors,
    }
    let finalResult = await EngineHooks.runPostHook(
      ~config,
      ~projectRoot=context.cwd,
      ~result,
      ~shell,
      ~process=proc,
      ~path,
      ~fs,
    )
    io.close()
    finalResult
  }
}
```

Key structural changes:
- `switch` + `| Error(e) => return Error(e)` pattern replaces nested `switch await { | Ok(...) => switch await { ... } }`
- `return` early-exits the async function instead of accumulating nestedOk values
- `io.close()` calls remain in EXACTLY the same positions as the original
- `Fetcher.clearCache()` and `cleanupOrphans` remain unconditional at the top
- `stagingDirRef` and signal handler setup remain after Phase1 success
- Dry run path returns early
- Phase2 error path calls `io.close()` then returns; success path runs post-hook then `io.close()`

**IMPORTANT**: ReScript's `return` in `async` blocks exits the function. Verify that the compiler supports this pattern. If `return` is not available, use a helper or restructure with `Promise.resolve(Error(...))`.

**Verify**: `pnpm build` → exits 0

If the build fails because `return` is not supported in ReScript async, restructure using an internal helper:

```rescript
// Alternative: use a helper function
let resolve: result<'a, 'b> => promise<result<'a, 'b>> = r => Promise.resolve(r)
```

Then replace `return Error(e)` with `resolve(Error(e))` throughout.

### Step 3: Verify behavior preservation with io.close() timing

The critical invariant: `io.close()` must be called exactly once on every code path. Verify by tracing each path:

1. Pre-hook error: `io.close()` at L36 ✓
2. Phase0 error: `io.close()` inside `EnginePhases.runPhase0` at line 17/30 ✓
3. Phase0 success → Phase1 error: `io.close()` inside `EnginePhases.runPhase1` at line 62 ✓
4. Phase0 success → Phase1 success → dry run: `io.close()` NOT called (dry run returns early, `io.close()` was already called after Phase0 at line 42) — WAIT, this is a problem.

Looking at the original code more carefully: `io.close()` is called at line 42 (after Phase0 success), BEFORE Phase1 runs. In the dry run path, `io.close()` was already called. In the non-dry-run path, `io.close()` is called again at line 121 (after post-hook). So `io.close()` is called TWICE on the success path — once after Phase0, once after Phase2.

This is the existing behavior. The refactored code must preserve it exactly.

**Verify**: `pnpm res:test` → all tests pass

### Step 4: Manual smoke test

Build the project and run a generation from an example template:

```bash
pnpm build
node dist/main.mjs generate react-app --output /tmp/smoke-test --force
```

**Verify**: Files are generated in `/tmp/smoke-test/` without errors

### Step 5: Run full test suite

**Verify**: `pnpm res:test` → all tests pass

## Test plan

- No new tests required — this is a structural refactor with NO behavior change.
- The existing test suite covers the full pipeline end-to-end.
- The manual smoke test verifies the real execution path.
- Verification: `pnpm res:test` → all pass + smoke test succeeds.

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `grep -n "switch await" src/application/engine/EngineOrchestrator.res` returns ≤2 matches (down from 4+)
- [ ] Maximum nesting depth in `run` is ≤3 levels (down from 6)
- [ ] `io.close()` calls remain in the same logical positions (grep and compare)
- [ ] Smoke test: `node dist/main.mjs generate react-app --output /tmp/smoke-test --force` succeeds
- [ ] No files outside the in-scope list are modified

## STOP conditions

- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).
- Plan 017 has not been applied (error channel is still `string`, not `phase2Error`).
- `pnpm build` fails after Step 2 with a ReScript syntax error that cannot be resolved by restructuring.
- Behavior ambiguity: the ordering between `io.close()` and error return is unclear on any path — STOP and report rather than guess.
- Test coverage gaps make the refactor unverifiable (e.g., no test exercises the dry-run path or the Phase2 error path).
- The `return` pattern is not supported in ReScript async and the alternative helper approach doesn't compile.

## Maintenance notes

- The accumulator/early-return style is easier to extend: adding a new phase just adds another `switch ... | Error(e) => return Error(e) | Ok(v) => v` block.
- `io.close()` is called in multiple places (after Phase0, inside Phase1 error, after Phase2). This is intentional — each phase manages its own I/O lifecycle. A future refactor could centralize `io.close()` in a `finally`-like pattern, but that's out of scope here.
- If Phase2's error type changes (e.g., plan 017's `phase2Error`), the `Error(e.message)` at the end may need to become `Error(e)` — check the return type of `run` after plan 017 is applied.
- The `Fetcher.clearCache()` call is unconditional — if it needs to be conditional in the future, move it inside the appropriate branch.
