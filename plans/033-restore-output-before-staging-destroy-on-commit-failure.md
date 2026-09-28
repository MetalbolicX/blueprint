# Plan 033: Restore output files before destroying staging on commit failure

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0267337..HEAD -- src/application/pipeline/Phase2.res src/application/pipeline/Phase2.resi src/application/pipeline/Commit.res src/application/pipeline/Commit.resi test/Phase2_test.res test/Commit_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (error-path only; happy path untouched)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `0267337`, 2026-09-27

## Why this matters

Blueprint's core promise is transactional generation: renders stage to a temp
dir and commit is atomic — "no partial writes reach output". Today that promise
breaks on a mid-commit failure: if copying the 5th of 10 staged files fails,
`Phase2.run`'s commit-error branch removes the staging dir WITHOUT restoring
already-committed output files — and the staging dir contains
`.blueprint-backup/`, the only copies of pre-existing files that were
overwritten. Result: new files stay in the output tree AND the user's original
files are irrecoverably lost. The shell-failure branch 40 lines earlier already
does the right thing (`rollbackOutput` then `rollback`); this plan makes the
commit-failure branch mirror it.

## Current state

ReScript 12 CLI, ESM, in-source compilation. 3-phase pipeline:
Phase1 renders to staging, Phase2 commits staging→output then cleans up.
Types involved (all confirmed at `0267337`):

- `src/application/pipeline/Commit.res:6` — `type backupEntry = { ... outputPath, backupPath }`
- `src/application/pipeline/Commit.res:16` — `type phase2Error = { message, partialCommit?: array<string>, catastrophic?: bool, failedRollbackFiles?: array<string> }` (optional-field record style; mirror in `Commit.resi:1-11`)
- `src/application/pipeline/Phase2.res:8` — `type phase2Result` (mirror in `Phase2.resi:1`)

The bug, in three pieces:

1. `Commit.res:40` — backups are written INSIDE staging:
   `let backupPath = path.join(stagingDir, path.join(backupDirName, targetPath))`
   (`backupDirName` = `.blueprint-backup`), so `Commit.rollback(stagingDir)`
   (an `rm -rf`) deletes the only backup copies.
2. `Commit.res:136-144` — `commitFiles` returns `backups` only in the `Ok`
   branch; the `Error` branch reports `partialCommit` (line 141) but drops
   `backups` (computed at line 129 from `successful`), so the caller cannot
   restore.
3. `Phase2.res:126-139` — commit-`Error` branch calls ONLY
   `Commit.rollback(stagingDir, ~tmpRoot, ~path, ~fs)`. Contrast the
   shell-failure branch at `Phase2.res:86-124`, which correctly calls
   `Commit.rollbackOutput(~committedFiles, ~backups, ~outputDir, ~path, ~fs)`
   FIRST (including a full catastrophic-error dance on rollback failure at
   lines 102-122), then `Commit.rollback(stagingDir, ...)`.

`rollbackOutput`'s signature is in `Commit.resi` (defined at `Commit.res:148`);
it takes `~committedFiles: array<string>`, `~backups`, `~outputDir`, `~path`,
`~fs` and restores backups over committed files (Phase2.res:87 is a working
call site to copy).

### Repo conventions to honor

- Error paths return `result<_, phase2Error>` records with optional fields
  (`?`) — match this style; do not introduce a new error type.
- `phase2Error` and `backupEntry` are defined in `Commit.res`/`Commit.resi`;
  `phase2Result` in `Phase2.res`/`Phase2.resi`. Keep the `.resi` mirrors in
  sync (ReScript requires it).
- No comments in source unless asked.
- Test style: model on `test/Phase2_test.res` — `open TestHelpers`,
  `testAsync("...", resolve => ...)`, port mocking via injected records; see
  the shell-failure restore test at `test/Phase2_test.res:707` ("run: shell
  failure restores overwritten files and deletes newly created files") and the
  rollback-failure mock at `:805` (injects "restore failed" for
  `.blueprint-backup` paths).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile (= typecheck) | `pnpm res:build` | exit 0 |
| Run all tests | `pnpm res:test` | all pass |
| Run only Phase2 tests | `npx retest ./test/Phase2_test.res.mjs` | all pass |
| Run only Commit tests | `npx retest ./test/Commit_test.res.mjs` | all pass |

There are NO `lint`/`typecheck` scripts — `pnpm res:build` is the type check.

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/Commit.res` + `Commit.resi` — carry `backups` in the error.
- `src/application/pipeline/Phase2.res` + `Phase2.resi` — restore output in the commit-error branch.
- `test/Phase2_test.res` — regression test (new).

**Out of scope** (do NOT touch):
- `ShellExecutor.res`, `Staging.res`, hooks, Engine modules — their error
  handling is separate work (plans 034+).
- The success path (`Phase2.res:60-85`) — it is correct.
- `rollbackOutput`/`rollback` implementations themselves (verified working;
  unit-tested at `test/Commit_test.res:38,89` and `test/Phase2_test.res:273,312`).

## Git workflow

- Branch: `fix/commit-failure-restore-output`
- Conventional commits, one per step below. Repo style: `fix(...)`, `test(...)`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Carry backups through the commit error

Commit message: `fix(commit): include backups in commitFiles error so callers can restore`

1. In `Commit.res`, add an optional field to `phase2Error`:
   `backups?: array<backupEntry>` (and mirror in `Commit.resi`).
2. In `commitFiles` (`Commit.res:136-142`), in the `errors->Array.length > 0`
   branch, attach the already-computed `backups` (line 129) to the error for
   both the `partialCommit->Array.length` cases (lines 140-141).

**Verify**: `pnpm res:build` → exit 0 (`.resi` sync enforced by compiler).

### Step 2: Restore output before removing staging in the commit-error branch

Commit message: `fix(phase2): restore committed output before destroying staging on commit failure`

Rewrite the commit-`Error` branch at `Phase2.res:126-139` to mirror the
shell-failure branch (`Phase2.res:86-124`):

1. Call `Commit.rollbackOutput(~committedFiles=err.partialCommit->Option.getOr([]), ~backups=err.backups->Option.getOr([]), ~outputDir, ~path, ~fs)`.
2. If restore succeeds → proceed to `Commit.rollback(stagingDir, ...)` as today;
   wrap its failure exactly as lines 130-137 do today.
3. If restore fails (`Error(failedRollbackFiles)`) → build the catastrophic
   error exactly like `Phase2.res:102-122` does (message, `partialCommit`,
   `catastrophic: true`, `failedRollbackFiles`), still attempt
   `Commit.rollback(stagingDir, ...)` afterwards, appending its failure to the
   message if it also fails.

Note: `err` at this point is the enriched error from Step 1, so
`err.partialCommit` and `err.backups` are populated when files were committed
before the failure.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Phase2_test.res.mjs ./test/Commit_test.res.mjs` → all existing tests still pass.

### Step 3: Regression test — commit failure restores overwritten files

Commit message: `test(phase2): commit failure restores backups and removes partial output`

Add to `test/Phase2_test.res`, modeled on the shell-failure restore test at
line 707 and the mock style at line 805:

- Setup: 3 files to commit; file 2 already exists in output with known content
  (so a backup is created for it); mock `fs.cp` to fail on the 3rd file's
  staged→output copy.
- Assert:
  1. `Phase2.run` returns `Error` with `partialCommit` non-empty.
  2. The overwritten file's content is back to its pre-run original (restored
     from `.blueprint-backup`).
  3. Newly committed files from the partial commit are deleted from output.
  4. Staging dir no longer exists.

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → all pass including the new test.

## Test plan

- New regression test above (happy-path commit, shell-failure restore, and
  rollback-failure paths are already covered by existing tests — do not
  duplicate).
- Full suite gate: `pnpm res:test` → all pass.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; new commit-failure-restore test exists and passes
- [ ] `grep -n "rollbackOutput" src/application/pipeline/Phase2.res` shows a call inside the commit-`Error` branch (after line 126), not only the shell-failure branch
- [ ] `grep -n "backups" src/application/pipeline/Commit.res` shows the error path of `commitFiles` returning them
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The excerpts above don't match live code (drift since `0267337`).
- `rollbackOutput`'s real signature in `Commit.resi` differs from the call at
  `Phase2.res:87` (adapt to the real signature only if trivially compatible;
  otherwise stop).
- Fixing this requires touching files outside the in-scope list (e.g.
  `phase2Error` gained new required consumers).
- The new regression test cannot force a mid-`commitFiles` cp failure with the
  existing mock infrastructure after two attempts.

## Maintenance notes

- If a future change adds more failure branches to `Phase2.run` (e.g. hook
  execution between commit and shell), each must decide: restore-then-clean,
  and must have a mirroring test.
- Reviewer should scrutinize: the catastrophic-error construction must not
  lose `partialCommit` when `backups` restore fails.
