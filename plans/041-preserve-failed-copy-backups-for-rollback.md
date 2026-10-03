# Plan 041: Carry failed-copy targets and backups into rollback

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/application/pipeline/Commit.res src/application/pipeline/Commit.resi src/application/pipeline/Phase2.res src/application/pipeline/Phase2.resi test/Phase2_test.res test/Commit_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches the critical rollback path; 033's semantics must not regress)
- **Depends on**: none (033 already landed — this builds on its `phase2Error` shape)
- **Category**: bug
- **Planned at**: commit `100b121`, 2026-10-01
- **Amended 2026-10-02**: adds Step 5 (test-only) — stabilize the two
  known-flaky signal-timing tests in `test/Phase2_test.res` ("signal rollback
  failure during commit surfaces a diagnostic" at `:287`, "script fails after
  file commit"). During plans 039/040 they failed 3× under full-suite load
  (race between the real-fs rollback chain and the main commit chain:
  assertion ran before the fake process recorded `exit(1)`), always passing
  focused. Test-side only; production signal wiring stays untouched.

## Why this matters

When a commit copy fails, the work item's error tuple drops the backup entry
it already created. Phase2's error path then rolls back only successfully
committed files and their backups, and afterwards deletes staging — which
holds the ONLY copy of the original file for the failed target. If the copy
failed after partially writing the destination (ENOSPC, EIO), the user's
original file is corrupt on disk and its backup is destroyed. This is a
data-loss window in the failure path of the "atomic commit" feature.

Scope note (do not relitigate): the SIGNAL path is already safe —
`onCommitting` fires BEFORE `fs.cp` (`Commit.res:102-104`) and pushes the
path+backup into `Phase2`'s refs (`Phase2.res:87-93`), so in-flight copies
are signal-tracked. This plan fixes the ERROR path's accounting only.

## Current state

At `100b121` (`src/application/pipeline/Commit.res`):

- `:81-142` — `commitFiles`: each work item runs
  `isWithinTree` → `backupIfOverwriting` → `onCommitting` → `lstat staged` →
  `cp`. Error tuples are `(string, option<backupEntry>)` and EVERY error site
  passes `None`:
  - `:97` outside-output-tree (no backup taken yet — `None` correct)
  - `:100` backup failed (no backup exists — `None` correct)
  - `:113` staged file is a symlink (backup MAY exist — dropped today)
  - `:125` cp failure (backup MAY exist — dropped today)
- `:130-136` — `errors` collects only the message; `partialCommit` and
  `backups` are built from SUCCESSFUL items only.
- `:136-156` — the `phase2Error` aggregates `partialCommit` + `backups`
  (successful items only).
- `src/application/pipeline/Phase2.res:160-196` — the commit `Error(err)`
  branch calls `Commit.rollbackOutput(~committedFiles=err.partialCommit ?? [], ~backups=err.backups ?? [], ...)`
  and then `Commit.rollback(stagingDir, ...)` which removes staging.
- `src/application/pipeline/Commit.res:170-218` — `rollbackOutput`: for each
  `outputPath`, restores from `backupByOutput` if a backup exists, else
  `rm`s it. (New-file targets without backups are removed; overwritten
  targets are restored — exactly the semantics failed targets need.)
- Plan 033's note in `plans/README.md`: `partialCommit` = "files successfully
  committed before failure, not the failed copy" — this plan must NOT change
  that documented meaning.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Phase2_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/Commit.res`
- `src/application/pipeline/Phase2.res`
- `test/Phase2_test.res` (and `test/Commit_test.res` if that is where
  commit-level tests live — check both)

**Out of scope** (do NOT touch):
- `partialCommit` semantics and its display in `Generate.res:79-95` — keep
  it "successfully committed files".
- The signal/rollback wiring in `Phase2.res:48-76` — already correct.
- `Staging.res`, `EngineLifecycle.res` — no changes needed.

## Git workflow

- Branch: `fix/041-failed-copy-rollback-accounting`
- Conventional commits, e.g. `fix(pipeline): restore failed-copy targets from their backups on rollback`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Carry the backup in the two error sites where one may exist

In `Commit.res` `commitFiles`, change the error tuples at the
staged-symlink site (`:113`) and the cp-failure catch (`:125`) from
`Error((message, None))` to `Error((message, backupOpt))` — `backupOpt` is
in scope (bound by the `Ok(backupOpt)` arm of `backupIfOverwriting`).
Leave `:97` and `:100` as `None` (no backup exists there — that is correct,
do not fabricate one).

**Verify**: `pnpm res:build` → exit 0 (expect the error-collection types to
break; fixed in Step 2).

### Step 2: Aggregate failed items with backups into `phase2Error`

Restructure the error aggregation in `commitFiles`:

1. Collect failed items as `(message, backupOpt)` pairs (keep `errors` as
   messages for the first-error message selection).
2. Extend the `phase2Error` type with two optional fields:
   `failedTargets?: array<string>` (the `destPath` of failed items) and
   `failedBackups?: array<backupEntry>` (the `Some` backups of failed items).
   Set them only when non-empty (match the existing `backups/partialCommit`
   optional-field style at `:136-156`).
3. Keep `backups`/`partialCommit` semantics EXACTLY as today (successful
   items only).

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → all pass EXCEPT the
new RED test you add in Step 4 (add it before this step if you want strict
RED first).

### Step 3: Merge failed items into the Phase2 error-path rollback

In `Phase2.res` `Error(err)` branch (`:160-196`), before calling
`rollbackOutput`:

```rescript
let rollbackTargets = err.partialCommit->Option.getOr([])
  ->Array.concat(err.failedTargets->Option.getOr([]))
let rollbackBackups = err.backups->Option.getOr([])
  ->Array.concat(err.failedBackups->Option.getOr([]))
```

Pass `~committedFiles=rollbackTargets, ~backups=rollbackBackups` to
`rollbackOutput`. Everything else in the branch (staging rollback,
catastrophic flags, error message construction) stays unchanged.

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → all pass.

### Step 4: Regression test (RED first)

In `test/Phase2_test.res` — model after the existing commit-failure
rollback test around `:1163` (it covers rollback of SUCCESSFUL items; this
adds the failed-item case). With the fake fs ports:

1. Two rendered files: A (new file, no existing target) and B (existing
   target with known original content).
2. Fake `fs.cp` succeeds for A, and for B: `backupIfOverwriting`'s cp
   (staging←dest) succeeds, then the commit cp (dest←staged) THROWS after
   mutating `destPath` content (fake port writes partial bytes then raises —
   simulate by setting dest content to "corrupt" then rejecting).
3. Assert: result is `Error`; A was removed (new file, no backup → rm);
   B's dest content equals the ORIGINAL content (restored from backup);
   staging was removed; and `phase2Error` carries the failed target info.

Write it first, confirm RED (today B stays corrupt and the backup dies with
staging), then confirm GREEN.

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → all pass; `pnpm res:test` → all pass.

### Step 5 (added 2026-10-02): Stabilize the signal-timing tests — test-side only

The two known-flaky tests race the real-fs signal-handler chain against the
main commit chain (see Status amendment). Fix the HARNESS, not the
assertions:

1. Preferred: make the registered signal handler's promise awaitable. If
   `EngineLifecycle.registerSignalHandlers`'s handler returns a promise,
   have the fake process (in the test's `makeSignalProcess`) capture that
   returned promise in a ref when `on` registers it; after `Phase2.run`
   resolves, await the captured promise before asserting. If the handler is
   NOT awaitable (sync or fire-and-forget), fall back to (2).
2. Fallback: a bounded wait helper in the test file — poll (5ms steps,
   ~2s cap) until BOTH the exit code is recorded AND the captured diagnostic
   is present, then run the assertions unchanged. Fail with a clear
   "rollback chain did not settle" message on timeout.
3. Assertions must remain BYTE-IDENTICAL in strength (same expected values,
   same conditions). Only the wait-before-assert changes.
4. Apply the same treatment to both flaky tests (and any other test in the
   file that asserts on the signal chain's side effects without awaiting
   it).

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → all pass; then run
`pnpm res:test` THREE consecutive times — all three must be green (the flake
fired roughly every 1-in-3 loaded runs; three consecutive greens is the
minimum bar, report the count).

## Test plan

- The RED→GREEN regression above.
- Keep all existing rollback tests green (especially 033's and the
  signal-rollback tests at `test/Phase2_test.res:211,287` — the latter two
  are ALSO the Step 5 stabilization targets; their assertions must survive
  byte-identical).
- Step 5: three consecutive green full-suite runs (recorded in the report).
- Optional extra: staged-symlink failure with existing target → backup
  restored (same mechanism, one extra assert).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new regression test
- [ ] Step 5: the two signal-timing tests' assertions unchanged (diff shows only wait/ordering changes) and THREE consecutive green full-suite runs recorded
- [ ] `grep -n "failedBackups" src/application/pipeline/Commit.res src/application/pipeline/Phase2.res` shows the new fields threaded end to end
- [ ] All pre-existing Phase2/Commit tests still pass unchanged (no weakened assertions)
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- `rollbackOutput`'s restore-vs-rm semantics turn out to differ from
  "backup exists → restore; no backup → rm" for the failed-target case.
- Making the fake fs simulate partial-write-then-throw requires changing
  production code (the test harness must do it via the injected port only).
- `phase2Error`'s shape has drifted from plan 033's description (re-read
  `plans/README.md` row 033 and reconcile before editing).

## Maintenance notes

- Reviewer focus: the merge in Phase2 must NOT double-restore a target that
  is in both `partialCommit` and `failedTargets` (it cannot be — a failed
  item never reaches the successful list — but assert it in the test).
- Follow-up (deferred): surface `failedTargets` in `Generate.res`'s
  partial-commit diagnostics so users see which files failed vs. rolled back.
- Related open item: rollback leaves created-but-empty parent dirs (known
  residual #8 in `odd/tasks/production-readiness-hardening.md`) — out of
  scope here.
