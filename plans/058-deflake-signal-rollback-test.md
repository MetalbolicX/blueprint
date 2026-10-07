# Plan 058: Make the signal-rollback diagnostic test deterministic (deflake)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/application/engine/EngineLifecycle.res test/Phase2_test.res`
> Semantic mismatch with the excerpts below is a STOP condition;
> line-number-only drift is benign.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

`test/Phase2_test.res:313` ("signal rollback failure during commit
surfaces a diagnostic") is the repo's known transient full-suite flake:
plans 040, 042 and 047 each recorded "after one known-flake rerun", the
hardening ledger logged it post-747, and plan 039 called it a known-open
follow-up. Root cause: the test polls for the rollback chain to settle
with a 2-second cap (`waitForSignalRollback`, 5 ms × 400 attempts); under
load the real async chain (signal → rollback → diagnostics → exit code)
can exceed 2 s and the test fails spuriously. The fix is to await the
chain directly instead of polling a timer — no timing window, no flake.

## Current state

- `test/Phase2_test.res:313-396` — the flaky test. It stubs `cp` so that
  copying from the backup dir rejects with `"restore failed"` and, on the
  staged-file copy, invokes the captured signal handler synchronously:
  ```rescript
  | Some(callback) =>
    callback()
    base.cp(src, dst, ~options?)
  ```
  It then polls:
  ```rescript
  ->Promise.then(_ => waitForSignalRollback(
    ~exitRecorded=() => Array.get(exitCodes.contents, 0) == Some(1),
    ~diagnosticPresent=() => %raw("globalThis.__testMessages.some(msg => String(msg).includes('Signal rollback failed'))"),
  ))
  ```
- `test/Phase2_test.res:28-43` — the poll helper (5 ms × 400 = 2 s cap):
  ```rescript
  let waitForSignalRollback: (
    ~exitRecorded: unit => bool,
    ~diagnosticPresent: unit => bool,
  ) => promise<unit> = %raw(`(exitRecorded, diagnosticPresent) => new Promise((resolve, reject) => {
    let attempts = 0;
    const poll = () => {
      if (exitRecorded() && diagnosticPresent()) return resolve();
      if (++attempts >= 400) return reject(new Error("rollback chain did not settle"));
      setTimeout(poll, 5);
    };
    poll();
  })`)
  ```
  Used only by this one test (`:380`).
- `src/application/engine/EngineLifecycle.res:95-136` —
  `registerSignalHandlers` wires `SIGINT`/`SIGTERM` (`:133-134`) to
  `handleSignal`, which runs `commitRollbackRef()` → `cleanupPath(stagingDir)`
  → `process.exit(1)`. **Read this function first**: determine whether the
  registered handler callback returns the rollback chain's promise
  (`promise<unit>`) or returns `unit` and lets it run detached.
- `src/application/pipeline/Phase2.res:58-84` — registers
  `commitRollbackRef` and emits the `"Signal rollback failed — output may
  be partially committed"` diagnostics (assertion target, unchanged).
- Sibling test `test/Phase2_test.res:233` ("signal during commit restores
  backups, removes staging, and exits non-zero") is already synchronous
  (handler invoked inside `cp`) and must stay untouched.

Conventions: tests are `testAsync(...)` with `resolve =>`; raw JS escape
hatches (`%raw`) are house-acceptable in tests (see the excerpts above).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0 |
| Focused test | `npx retest ./test/Phase2_test.res.mjs` | all pass |
| Repeated focused run | `for i in $(seq 1 20); do npx retest ./test/Phase2_test.res.mjs \|\| break; done` | 20/20 green |
| Full suite | `pnpm res:test` | all pass, exit 0 |

## Scope

**In scope**:
- `test/Phase2_test.res` (the one test; remove `waitForSignalRollback` if it becomes unused)
- `src/application/engine/EngineLifecycle.res` — **only if** the handler
  callback does not already return the chain promise; then thread the
  promise through (no behavior change)

**Out of scope**:
- The sibling signal test at `:233`; `Phase2.res` diagnostics; exit-code
  semantics; any timeout/threshold tuning.

## Git workflow

- Branch: `test/058-deflake-signal-rollback`
- Commit style: `test(phase2): await the signal rollback chain directly instead of polling`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: Inspect the handler's return shape

Read `EngineLifecycle.res:95-136`. Decide: does the callback stored via
`Ports.process.onSignal` return the rollback chain promise?

- **If yes** → go to Step 2 (pure test change).
- **If no** → minimally change `handleSignal`/the registered callback so
  the callback returns the chain's `promise<unit>` (e.g. make the
  callback `async` / return the composed promise). Production behavior is
  identical — signal delivery ignores the return value — but the test can
  now await it. Keep `process.exit(1)` as the LAST step of the chain.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Phase2_test.res.mjs` → all pass (unchanged behavior).

### Step 2: Rewrite the test to await the chain

In `test/Phase2_test.res:313-396`: where the `cp` stub currently does
`callback(); base.cp(...)`, capture the returned promise instead, e.g.
store it in a `ref` (`chainPromise`). After `Phase2.run(...)` settles,
replace the `waitForSignalRollback(...)` block with a direct await:

```rescript
->Promise.then(_ => chainPromise.contents)
```

then assert exactly as today (synchronously, no polling):
`assert_true(String.includes(joined, "Signal rollback failed"))` and
`assert_eq(Array.get(exitCodes.contents, 0), Some(1))`, plus the existing
cleanup/restore of `console.error` and `resolve()`.

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → all pass.

### Step 3: Remove the dead poller

`grep -n "waitForSignalRollback" test/` — if the helper (`:28-43`) now has
zero callers, delete it.

**Verify**: `grep -n "waitForSignalRollback" test/Phase2_test.res` → no matches.

### Step 4: Flake gate

**Verify**: `for i in $(seq 1 20); do npx retest ./test/Phase2_test.res.mjs || break; done`
→ 20 consecutive green runs; then `pnpm res:test` → all pass.

## Test plan

- No new tests; the target test's assertions are unchanged — only the
  settle mechanism changes from timing-poll to direct await.
- 20× repeat run is the anti-flake evidence.

## Done criteria

- [ ] `waitForSignalRollback` gone (or provably still used elsewhere)
- [ ] `npx retest ./test/Phase2_test.res.mjs` passes 20× consecutively
- [ ] `pnpm res:test` exits 0
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The handler chain cannot be awaited without reordering
  `process.exit(1)` relative to the diagnostics (semantics would change).
- The stored callback is invoked from a context that discards its promise
  AND threading it through requires touching files outside scope.
- The 20× gate still shows a failure — report the failure output; do not
  raise timers or retry loops to mask it.

## Maintenance notes

- If a future change re-adds real-signal timing tests, prefer the
  capture-and-await pattern established here over timer polling.
- Reviewer focus: Step 1's src change (if needed) must not alter handler
  registration semantics for `SIGINT`/`SIGTERM`.
