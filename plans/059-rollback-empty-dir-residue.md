# Plan 059: Rollback removes directories the failed commit created

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/application/pipeline/Commit.res src/application/pipeline/Phase2.res test/Phase2_test.res`
> Semantic mismatch with the excerpts below is a STOP condition;
> line-number-only drift is benign. NOTE: plan 057 also touches
  `Commit.res` / `test/Phase2_test.res` — if it already landed, re-read
  the live code and adapt line references; the design here is independent.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (rollback semantics — must never delete pre-existing directories)
- **Depends on**: none (sequence after plan 057 to avoid test-file churn)
- **Category**: bug
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

`commitFiles` creates parent directories with `mkdir -p` before each
copy, but `rollbackOutput` only removes **files** (`rm` with
`recursive: false`). When a commit fails and rolls back — or a signal
aborts mid-commit — every directory the commit created stays behind as
empty residue in the user's output tree. This is audit item M1, recorded
twice as "unchanged" (`odd/tasks/production-readiness-hardening.md:115`
#8, `plans/041-…md:242` "related open item"). Users see ghost directory
skeletons after every failed generation. The fix: record which
directories the commit created and remove exactly those (deepest-first)
during rollback — never a directory that existed before.

## Current state

- `src/application/pipeline/Commit.res:116` — directory creation inside
  `commitFiles` (before each copy):
  ```rescript
  let _ = await fs.mkdir(destDir, ~options={recursive: true})
  ```
  `mkdir` with `recursive: true` silently creates ALL missing ancestors
  and reports nothing — created-ness must be probed, not inferred.
- `src/application/pipeline/Commit.res:159-226` — `rollbackOutput`:
  containment re-check per work item (`:177-184`), then per-file removal:
  ```rescript
  | None => {
      try {
        await fs.rm(outputPath, ~options={recursive: false})
        Ok()
      } catch {
      | JsExn(obj) => ... if String.includes(msg, "ENOENT") { Ok() } else { Error(...) }
  ```
  `committedFiles` are file paths only. No `rmdir`/empty-dir removal
  exists anywhere in `src/` (`grep -rn "rmdir" src/` → no matches).
- `src/application/pipeline/Commit.res:232-253` — `rollback` (staging-dir
  removal only, tmpRoot-contained).
- `src/application/pipeline/Phase2.res:58-84` — signal/commit-failure
  path calling `Commit.rollbackOutput` via `commitRollbackRef` / the
  commit error branch.
- Rollback tests in `test/Phase2_test.res`: `:192` containment,
  `:522` `rollback: removes staging directory`, `:538` `rollbackOutput:
  returns Error with failed restore path when restore throws`, `:577`
  failed new-file deletion, `:608` `rollback` rm failure; failure-path
  integration runs at `:1090`, `:1174`, `:1244`, `:1314`. **No test
  asserts empty-dir cleanup (no such test name exists).**

Conventions: `result<'a, string>` error channel; injected `Ports.fileSystem`;
error accounting style for rollback failures is visible in the `:538`/`:577`
tests — match it.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0 |
| Focused tests | `npx retest ./test/Phase2_test.res.mjs` | all pass |
| Full suite | `pnpm res:test` | all pass, exit 0 |

Test-first: observe RED, then GREEN.

## Scope

**In scope**:
- `src/application/pipeline/Commit.res` / `.resi` (record created dirs; remove them in `rollbackOutput`)
- `src/application/pipeline/Phase2.res` (thread the created-dirs list to rollback calls)
- `test/Phase2_test.res`

**Out of scope**:
- Staging-dir `rollback` (`:232-253`) — unchanged
- Backup-restore semantics, `cleanupOrphans`, output-dir legacy handling
- Deleting pre-existing-but-now-empty directories (explicitly forbidden below)

## Git workflow

- Branch: `fix/059-rollback-empty-dir-residue`
- Commit style: `fix(commit): remove commit-created empty dirs on rollback`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: RED — rollback leaves created dirs behind

New tests in `test/Phase2_test.res` (model after `:538-576` for direct
`rollbackOutput` calls):

1. `rollbackOutput: removes commit-created empty parent dirs deepest-first`
   — output tree with a pre-existing `output/`; a commit whose file went
   to `output/a/b/c/file.txt` where `a`, `a/b`, `a/b/c` did NOT exist.
   Call `rollbackOutput` with the committed file + the created dirs (the
   exact signature depends on Step 2 — write the test against the
   INTENDED new signature). Assert `output/a` no longer exists and
   `output/` still does.
2. `rollbackOutput: preserves pre-existing empty dirs` — an empty dir
   that existed before the commit (not in the created list) must survive
   rollback.

Run first against current code with the created-dirs argument defaulted
away or ignored: assertion 1 must FAIL (dirs remain) — that is the RED.
Assertion 2 should already hold.

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → test 1 FAILS, test 2 passes. Record RED.

### Step 2: Record created dirs in `commitFiles`

In `Commit.res`:
- Before the `mkdir` at `:116`, probe ancestors of `destDir`: walk from
  `destDir` upward toward the output root; for each path that does not
  yet exist (`fs.fileExists` / `stat` absence), record it; stop at the
  first existing ancestor or the output root. Dedup across files (a
  checked-set keyed by path string) so repeated files don't re-stat.
- Carry the collected `createdDirs: array<string>` in `commitFiles`'
  result so callers (and its `.resi`) expose it.

Keep the probe read-only and best-effort-free: a probe error is a real
commit error (fail closed, like the rest of `commitFiles`).

**Verify**: `pnpm res:build` → exit 0; existing `test/Phase2_test.res` commit tests still pass.

### Step 3: Remove created dirs in `rollbackOutput`

- Extend `rollbackOutput` with an optional `~createdDirs: array<string>=?`
  (default `[]` keeps every existing caller/test compiling).
- After file removals/restores: sort `createdDirs` deepest-first (by path
  segment count), and for each: `fs.rm(dir, ~options={recursive: false})`.
  - Success or `ENOENT` → fine.
  - `ENOTEMPTY` (something else legitimately lives there now) → fine, skip.
  - Any other error → collect into the existing failure-accounting
    result exactly as file-removal errors are handled.
- Apply the same containment re-check used for files (`:177-184`) to each
  directory before removing it. Never remove a path outside the output
  root, never `recursive: true`.

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → both Step-1 tests pass (GREEN).

### Step 4: Thread through Phase2

In `Phase2.res` (`:58-84`): pass `commitFiles`' `createdDirs` into every
`rollbackOutput` call (signal path and commit-error path). Add one
assertion to an existing failure-path integration run (`:1090`, `:1174`,
`:1244`, or `:1314`): the commit-created parent dir is gone after the
failure.

**Verify**: `npx retest ./test/Phase2_test.res.mjs` → all pass; `pnpm res:test` → all pass, exit 0.

## Test plan

- New: the two Step-1 tests + one integration assertion (Step 4).
- Existing rollback tests pin current semantics — all must stay green.

## Done criteria

- [ ] `pnpm res:test` exits 0 with new tests passing
- [ ] RED evidence recorded for Step 1 test 1
- [ ] `grep -n "recursive: true" src/application/pipeline/Commit.res` shows no new use in the rollback path
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- `fs.rm` with `recursive: false` cannot remove an empty dir through the
  current `Ports.fileSystem` binding (verify in Step 1; report rather
  than widening the port).
- Threading `createdDirs` requires changing callers outside
  `Commit.res`/`Phase2.res` (grep callers of `rollbackOutput` first).
- Any existing rollback test flips semantics.

## Maintenance notes

- Deliberate non-goal: cleaning pre-existing empty dirs — that would be a
  behavior change (deleting user state), not a rollback fix.
- Interacts with plan 057 (same files); sequence 057 → 059.
- Reviewer focus: the upward ancestor probe (bounded walk, no infinite
  loop at the output root) and the containment re-check on directory
  removal.
