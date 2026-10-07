# Plan 057: Stop the orphan sweep from deleting an active run's staging directory

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/application/engine/EngineLifecycle.res src/application/pipeline/Phase1.res src/application/pipeline/Commit.res test/Engine_test.res test/Phase1_test.res test/Phase2_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> semantic mismatch, treat it as a STOP condition. (Line-number-only drift
> from LAN-registry branch additions is benign — match by symbol names.)

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches the live pipeline write path; mitigation: best-effort heartbeat writes that never fail a run)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

The pre-run orphan sweep deletes a staging directory when its name
timestamp is ≥30 min old AND its directory mtime is ≥15 min old. A
directory's mtime only changes when entries are added or removed — not
when files inside are written. So a **legitimately active run** that
started >30 min ago and goes >15 min without adding a new staging entry
(e.g. slow prompts, big renders, long commit copies) gets its staging
deleted mid-run: the run then fails or, worse, commits from a half-missing
tree. The code itself records this as a known residual risk (see the
comment excerpted below); this plan closes it with a heartbeat marker.

## Current state

- `src/application/engine/EngineLifecycle.res` — owns the sweep.
  Constants (`EngineLifecycle.res:4-6`):
  ```rescript
  let stagingDirPrefix = "blueprint-"
  let backupDirName = ".blueprint-backup"
  let staleThresholdMs = 30 * 60 * 1000
  let recentMtimeThresholdMs = 15 * 60 * 1000
  ```
  Sweep decision (`EngineLifecycle.res:56-70`):
  ```rescript
  if String.startsWith(entry, stagingDirPrefix) {
    switch parseStagingDirTimestamp(entry) {
    | Some(createdAt) if nowMs - createdAt >= staleThresholdMs => {
        let fullPath = path.join(resolvedTmpRoot, entry)
        try {
          let stat = await fs.stat(fullPath)
          let oldEnoughByMtime = switch stat.mtimeMs {
          | Some(mtimeMs) => nowMsFloat -. mtimeMs >= recentMtimeThresholdMs->Int.toFloat
          | None => false
          }
          if stat.isDirectory() && oldEnoughByMtime {
            // Residual risk: an active run idle for more than 15 minutes between writes may be swept; a heartbeat marker is a follow-up.
            await cleanupPath(~target=fullPath, ~fs)
  ```
- `src/application/pipeline/Phase1.res:113-114` — staging creation:
  ```rescript
  let ts = Date.now()->Float.toInt->Int.toString
  let tmpDir = await fs.makeStagingDir("blueprint-" ++ ts ++ "-")
  ```
- `src/application/pipeline/Commit.res:116` — per-file parent creation
  inside `commitFiles`: `let _ = await fs.mkdir(destDir, ~options={recursive: true})`
  (copies staging→output; staging itself gets no writes during Phase 2).
- `src/application/engine/EngineOrchestrator.res:45-49` — sweep caller;
  dry runs skip it (plan 044 ruling — keep that).
- Existing sweep tests in `test/Engine_test.res`: `:683` "preserves
  old-name staging dirs with recent mtime", `:700` "removes staging dirs
  old by name and mtime", `:718` "round-trips timestamp…", `:743`
  "preserves fresh blueprint staging dirs", `:823`/`:841`/`:858` backup-leak
  cases. **Two vacuous stubs to repair in this plan**: `:739` "removes
  stale blueprint staging dirs" and `:873` "cleans orphaned staging dirs
  and backup leaks before execution" — their bodies are only
  `Promise.resolve()`; they assert nothing today.
- No heartbeat exists anywhere (`grep heartbeat src/` hits only the
  residual-risk comment above).

Repo conventions: errors flow through `result<'a, string>`; all IO goes
through injected `Ports` members (AGENTS.md hexagonal rule — application
code never imports infrastructure directly). Test style: `testAsync`
with `resolve =>` and `TestPorts` stubs — model after
`test/Engine_test.res:683-717`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0, no new warnings |
| Full build | `pnpm build` | exit 0 (ReScript then Rolldown) |
| Focused tests | `npx retest ./test/Engine_test.res.mjs` (same for `Phase1_test`, `Phase2_test`) | all pass, exit 0 |
| Full suite | `pnpm res:test` | all pass, exit 0 |

There is no lint/typecheck/format script in this repo. Tests are
test-first by house rule: observe RED, then GREEN.

## Scope

**In scope** (the only files you should modify):
- `src/application/engine/EngineLifecycle.res` / `.resi` (heartbeat constant + touch helper + sweep check)
- `src/application/pipeline/Phase1.res` (write heartbeat at staging creation and after each staging file write)
- `src/application/pipeline/Commit.res` (refresh heartbeat during the commit copy loop)
- `test/Engine_test.res`, `test/Phase1_test.res`, `test/Phase2_test.res`

**Out of scope** (do NOT touch):
- `EngineOrchestrator.res` (sweep caller unchanged; dry-run skip stays)
- Backup-dir sweep logic (`.blueprint-backup` handling stays as-is)
- Any change to the 30-min/15-min thresholds

## Git workflow

- Branch: `fix/057-orphan-sweep-heartbeat` (repo convention:
  `<type>/NNN-slug`, see `fix/039-shell-enabled-gate`, `fix/045-private-exclusive-staging`)
- Conventional Commits, e.g. `fix(engine): preserve staging dirs with a fresh heartbeat marker`
- Never commit on `main`; do NOT push or open a PR unless instructed.

## Steps

### Step 1: RED — sweep tests for the heartbeat rule

In `test/Engine_test.res`, model after the existing `cleanupOrphans` tests
(`:683-717` — reuse however those tests create old-named dirs and set
mtimes; read them first and copy their technique exactly):

1. New test `cleanupOrphans: preserves old staging dir with a fresh heartbeat`
   — staging dir whose **name timestamp is >30 min old** and whose **dir
   mtime is >15 min old**, but containing `.blueprint-heartbeat` with a
   **recent mtime**. Assert the dir still exists after `cleanupOrphans`.
   (This fails today — that is the RED.)
2. New test `cleanupOrphans: sweeps old staging dir without a heartbeat`
   — same age setup, no heartbeat file. Assert removed. (Passes today;
   guards the regression.)

**Verify**: `npx retest ./test/Engine_test.res.mjs` → test 1 FAILS
(preservation), test 2 passes. Record the RED output.

### Step 2: GREEN — heartbeat check in the sweep

In `EngineLifecycle.res`:
- Add `let heartbeatName = ".blueprint-heartbeat"` next to the constants.
- Add a best-effort touch helper (never throws):
  ```rescript
  let touchHeartbeat: (~fs: Ports.fileSystem, ~stagingDir: string, ~path: Ports.path) => promise<unit>
  ```
  writing an empty string to `path.join(stagingDir, heartbeatName)`,
  catching all errors and resolving `()` on failure.
- In the sweep branch, after `oldEnoughByMtime` is true and before
  `cleanupPath`: stat `path.join(fullPath, heartbeatName)`.
  - No such file (ENOENT-style absence) → sweep as today.
  - Heartbeat exists and its mtime is `< recentMtimeThresholdMs` old →
    **preserve** (skip removal, continue).
  - Heartbeat stat fails with anything else → **preserve** (fail-open,
    conservative).
  - Heartbeat exists but is itself stale → sweep as today.

**Verify**: `npx retest ./test/Engine_test.res.mjs` → all pass including
both new tests.

### Step 3: Phase1 writes the heartbeat

In `Phase1.res`:
- After `makeStagingDir` (`:113-114`): `await EngineLifecycle.touchHeartbeat(...)`.
- After each successful staging file write in the render loop: refresh the
  heartbeat (same call). Heartbeat failures are already swallowed by the
  helper — a heartbeat problem must never fail a render.

Add one test in `test/Phase1_test.res`: after a successful `Phase1.run`
with ≥1 rendered file, the staging dir contains `.blueprint-heartbeat`.

**Verify**: `npx retest ./test/Phase1_test.res.mjs` → all pass.

### Step 4: Commit refreshes the heartbeat during copies

In `Commit.res` `commitFiles` loop: after each successful `cp`, refresh
the heartbeat on the **staging** dir (the run is still active while
Phase 2 copies; staging's own mtime does not change during copies).

Add one test in `test/Phase2_test.res` (Commit tests live here — model
after `:522-536`): with a fake fs that records `writeFile` calls, a
2-file commit refreshes the heartbeat (≥1 write to the heartbeat path
after the first copy).

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → all pass.

### Step 5: Repair the two vacuous stubs

`test/Engine_test.res:739` and `:873` resolve immediately without
asserting. Give each a real body: create the fixtures their names promise
(stale staging dir / stale staging dir + backup leak), run the real
`cleanupOrphans` (or `run`, respectively), assert removal actually
happened. If `:873` cannot drive the full `run` path cheaply, assert via
`cleanupOrphans` and rename the test accordingly — do not leave it
vacuous.

**Verify**: `npx retest ./test/Engine_test.res.mjs` → all pass, and
`grep -n "Promise.resolve()" test/Engine_test.res` shows no test body
consisting solely of that.

### Step 6: Full gate

**Verify**: `pnpm build` → exit 0, no new warnings; `pnpm res:test` →
all pass, exit 0.

## Test plan

- New: the two Step-1 sweep tests, the Phase1 heartbeat-exists test, the
  Commit heartbeat-refresh test; repaired bodies for the two stubs.
- Existing sweep/preserve tests must stay green (they pin today's
  semantics for dirs without heartbeats).

## Done criteria

- [ ] `pnpm build` exits 0 with no new warnings
- [ ] `pnpm res:test` exits 0; new tests present and passing
- [ ] `grep -rn "heartbeat" src/` shows the marker logic; sweep preserves a fresh-heartbeat dir
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- The existing tests provide no mechanism to set old mtimes (Step 1's RED
  fixture cannot be built) — report instead of inventing clock fakes.
- `Ports.fileSystem` has no writable member usable for the empty heartbeat
  write without a signature change — report; do not widen Ports unilaterally.
- Any existing sweep test's semantics change (a preserve test starts
  sweeping or vice versa).

## Maintenance notes

- The heartbeat covers "idle between writes". A run that hangs before its
  FIRST staging write still relies on the dir-name timestamp (30 min) —
  unchanged by design.
- Future change interacting here: plan 059 (rollback empty-dir residue)
  also touches `Commit.res` / `test/Phase2_test.res`; sequence this plan
  first.
- Reviewer focus: the sweep's fail-open stat-error arm, and that
  heartbeat write failures never propagate into render/commit results.
