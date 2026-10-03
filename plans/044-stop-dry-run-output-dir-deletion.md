# Plan 044: Stop dry-run from deleting the legacy output backup dir

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/application/engine/EngineOrchestrator.res src/application/engine/EngineLifecycle.res src/application/engine/EngineLifecycle.resi src/interfaces/cli/commands/Generate.res test/Engine_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (narrows a destructive cleanup; nothing else consumes the dir)
- **Depends on**: none (but coordinate with plan 045 — both touch staging/backup naming)
- **Category**: bug
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

Every engine run calls `cleanupOrphans` BEFORE the dry-run branch is
evaluated, and that cleanup recursively deletes
`<outputDir>/.blueprint-backup` on existence alone — no marker, no age
check. Current code never creates that dir (backups live in staging since
plan 033), so it only ever deletes LEGACY leftovers or a USER directory that
happens to have that name — and it does so even when the user asked for a
dry run, which must never mutate the output directory. A dry run that
deletes a directory is a contract violation users cannot anticipate.

## Current state

At `100b121`:

- `src/application/engine/EngineOrchestrator.res:40-45` — Phase 0 setup runs
  unconditionally: `Fetcher.clearCache()` then
  `await EngineLifecycle.cleanupOrphans(~outputDir, ~fs, ~path)` — BEFORE the
  dry-run branch at `:182-198` resolves dry-run from the merged config.
- `src/application/engine/EngineLifecycle.res:31-99` — `cleanupOrphans`:
  (a) sweeps stale `blueprint-*` entries in the temp root (30-min age by
  parsed name timestamp + 15-min mtime — `:52-70`); (b) at `:81-99`, if
  `<outputDir>/.blueprint-backup` exists, `cleanupPath` removes it
  recursively with NO marker/age policy. `cleanupPath` (`:12-19`) swallows
  all errors.
- `src/application/pipeline/Commit.res:23` — `backupDirName =
  ".blueprint-backup"`; backups are created INSIDE staging
  (`Commit.res:34-48`), so the output-dir copy is legacy-only today.
- `test/Engine_test.res` — has a test enshrining "removes blueprint backup
  leak dirs" (grep `blueprint-backup` in it to find the exact test); it runs
  a NON-dry-run engine path.
- Dry-run resolution: `EngineOrchestrator.res:182-198` derives it from the
  merged config AFTER Phase 0 setup.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Engine_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/application/engine/EngineOrchestrator.res`
- `src/application/engine/EngineLifecycle.res` (+ `.resi` if the signature changes)
- `test/Engine_test.res`

**Out of scope** (do NOT touch):
- The temp-root staging sweep (`:52-70`) — it only touches blueprint's own
  stale temp dirs; leave its thresholds (ledger residuals #10 track it).
- `Commit.res` backup placement — already correct (staging).
- `Cli.res` / `Generate.res` dry-run plumbing — fix inside the engine.

## Git workflow

- Branch: `fix/044-dry-run-no-output-dir-deletion`
- Conventional commits, e.g. `fix(engine): skip destructive cleanup on dry runs`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Resolve dry-run before Phase 0 cleanup

In `EngineOrchestrator.run`, hoist the dry-run computation (currently at
`:182-198`) so it is available before the `cleanupOrphans` call at `:42`.
If the computation depends on values not yet built at that point (e.g. a
context built later), refactor minimally: extract the dry-run derivation
into a small helper evaluated from the merged config + any earlier inputs —
do NOT reorder other Phase 0 work. If dry-run genuinely cannot be known
before context construction, move ONLY the `cleanupOrphans` call to after
dry-run resolution instead (equivalent effect; keep `Fetcher.clearCache()`
where it is).

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → all pass (no
behavior change yet for non-dry runs).

### Step 2: Skip the cleanup on dry runs

Pass the dry-run flag into `cleanupOrphans` (new labeled param, e.g.
`~dryRun: bool`) or guard the call in the orchestrator:

- When `dryRun=true`: do not run `cleanupOrphans` at all (neither the tmp
  sweep nor the output-dir removal) — a dry run must not mutate the
  filesystem beyond its own staging dir.
- When `dryRun=false`: keep today's behavior exactly, but add a visible
  `Console.warn("Removing legacy backup dir: " ++ backupDir)` right before
  the output-dir removal in `EngineLifecycle.res` (visibility for a user who
  legitimately owns such a directory).

**Verify**: `pnpm res:build` → exit 0.

### Step 3: RED→GREEN tests

In `test/Engine_test.res` (reuse the existing leak-dir test's fixtures):

1. Dry-run engine invocation with `outputDir/.blueprint-backup` present
   (fake fs) → the dir STILL EXISTS after the run (RED today: removed).
   Also assert no other output-dir mutation happened (fake fs records
   writes/removes under outputDir).
2. Non-dry-run with the dir present → removed, run succeeds (the existing
   enshrined test, possibly extended with the warning assertion).
3. Non-dry-run with NO dir present → unchanged behavior (regression guard).

**Verify**: `npx retest ./test/Engine_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The 3 cases above; model after the existing "removes blueprint backup leak
  dirs" test in `test/Engine_test.res`.
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new dry-run preservation test
- [ ] A dry-run engine test asserts `outputDir/.blueprint-backup` survives AND no output-dir mutations occur
- [ ] Non-dry-run removal behavior still passes
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Dry-run is not derivable from the merged config alone (e.g. it depends on
  prompt answers) — surface the wiring; do not guess.
- Moving `cleanupOrphans` breaks an ordering assumption elsewhere (grep
  `cleanupOrphans` for all callers first).
- The existing leak-dir test asserts removal under a DRY-run invocation
  (that would be an intentional contract this plan contradicts).

## Maintenance notes

- Accepted residual: on REAL runs, a user-owned directory named exactly
  `.blueprint-backup` in the output dir is still removed (legacy-leak
  cleanup is enshrined by tests, and no marker can distinguish legacy leaks
  from user dirs). The warning added in Step 2 is the mitigation; if that
  tradeoff is unacceptable, the alternative is a one-release deprecation
  window with a prompt — a product decision, not this plan.
- Plan 045 changes staging-dir naming/creation; its `parseStagingDirTimestamp`
  dependency lives in the same file — execute 044 and 045 sequentially and
  re-run both test files.
