# Plan 037: Resolve existing ancestors in PathSecurity's ENOENT fallback; remove the always-false stat symlink flag

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0267337..HEAD -- src/infrastructure/path/PathSecurity.res src/infrastructure/adapters/NodeJsFileSystem.res src/infrastructure/adapters/NodeJsFileSystem.resi test/PathTraversal_test.res test/PathSecurity_test.res test/NodeJsFileSystem_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (containment logic is on every write path — false positives
  would break legitimate non-existent target paths)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `0267337`, 2026-09-27

## Why this matters

Path containment (`isWithinTree`) guards every template write. When the target
leaf doesn't exist yet (the COMMON case — templates write new files), realpath
fails with ENOENT and the code falls back to the purely lexical path, skipping
symlink resolution of existing intermediate directories. A directory symlink
already inside the output tree pointing outside (poisoned checkout, prior
compromised run) plus a non-existent leaf therefore passes containment, and
the subsequent write follows the link — an escape outside the output dir.
The commit-time re-validation (`Commit.res:92`) uses the same helper, so it
inherits the hole. Separately, the filesystem adapter exposes
`isSymbolicLink` on `stat` results — which follows symlinks, so the flag is
always false; dead weight that would silently defeat any future check.

## Current state

At `0267337`:

- `src/infrastructure/path/PathSecurity.res:25-27` — `_resolveRealPath`
  catch: `code == "ENOENT" || code == "ENOTDIR"` → `Ok(path)` returns the
  LEXICAL path unchanged (symlinks in existing ancestors unresolved).
- `src/infrastructure/path/PathSecurity.res:46-48` — the root-side resolution
  (outputDir side) resolves fine; not affected.
- `src/infrastructure/path/PathSecurity.res:60-71` — boundary check: correct
  `/`-or-`\` boundary prefix comparison (verified sound; do not touch).
- `src/application/pipeline/Commit.res:92` — commit re-validates via the same
  `isWithinTree` (inherits the fallback; fixed transitively here).
- `src/infrastructure/adapters/NodeJsFileSystem.res:57-63` — `stat` wrapper
  reads `isSymbolicLink` off a following-symlink stat via `Obj.magic` →
  always false (Node semantics). A comment at `:57` even notes stat follows
  symlinks.
- `src/infrastructure/adapters/NodeJsFileSystem.res:67-77` — the `lstat` path
  is correct (does not follow).
- Consumers of `isSymbolicLink`: ONLY `Commit.res:44` and `Commit.res:105`,
  both on `lstat` results (exhaustively verified at `0267337`). No security
  check depends on the stat flag — this is hygiene, not an active hole.
- Tests: `test/PathTraversal_test.res:96,106` (containment cases),
  `test/PathSecurity_test.res`, `test/NodeJsFileSystem_test.res`.

### Design decision (already made — do not relitigate)

Walk-up resolution: on ENOENT/ENOTDIR at the leaf, realpath the deepest
EXISTING ancestor, re-append the non-existent tail components, then run the
existing boundary check unchanged. This preserves every legitimate
non-existent-leaf case (no false positives) while closing the symlinked-parent
hole.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile (= typecheck) | `pnpm res:build` | exit 0 |
| Run all tests | `pnpm res:test` | all pass |
| Run path tests only | `npx retest ./test/PathTraversal_test.res.mjs ./test/PathSecurity_test.res.mjs ./test/NodeJsFileSystem_test.res.mjs` | all pass |

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/path/PathSecurity.res` — ancestor resolution.
- `src/infrastructure/adapters/NodeJsFileSystem.res` (+ `.resi` if the stat
  type is declared there) — remove `isSymbolicLink` from the `stat` result.
- `test/PathTraversal_test.res`, `test/PathSecurity_test.res`,
  `test/NodeJsFileSystem_test.res` — new/adjusted cases.

**Out of scope** (do NOT touch):
- The boundary-check function at `PathSecurity.res:60-71` (verified sound).
- `Commit.res` (fixed transitively; its re-validation stays as-is).
- Any SsrfGuard/fetcher logic.

## Git workflow

- Branch: `fix/pathsecurity-ancestor-realpath`
- Conventional commits: `fix(...)`, `test(...)`, `refactor(...)`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Resolve the deepest existing ancestor on ENOENT

Commit message: `fix(path): resolve existing ancestors before containment check on non-existent leaves`

In `PathSecurity.res`:

1. Add a helper `resolveExistingAncestor` (local, or beside
   `_resolveRealPath`): given the full path, split into components; from the
   leaf upward, attempt `realpath` on progressively shorter prefixes until one
   succeeds (the file system port's realpath — use the same fs port the
   module already receives); on the first success, join that resolved prefix
   with the remaining unresolved tail components.
2. If NO prefix resolves up to and including the root of the check, keep the
   current lexical fallback (behavior unchanged).
3. In the ENOENT/ENOTDIR catch (`:25-27`), return
   `Ok(resolveExistingAncestor(path))` instead of `Ok(path)`.
4. EACCES guard at `:28` unchanged.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/PathTraversal_test.res.mjs ./test/PathSecurity_test.res.mjs` → existing tests pass (legitimate non-existent paths must still pass containment).

### Step 2: Remove the always-false stat symlink flag

Commit message: `refactor(fs): drop always-false isSymbolicLink from stat results`

In `NodeJsFileSystem.res:57-63`: remove `isSymbolicLink` from the `stat`
result mapping (the `lstat` path at `:67-77` keeps its correct flag). Update
the stat record type in the `.resi` if declared there. Compiler will surface
any consumer (audit found none on stat; test mocks may construct the field —
delete those mock fields).

**Verify**: `pnpm res:build` → exit 0; `grep -rn "isSymbolicLink" src/` → only `lstat`-related sites remain (`NodeJsFileSystem.res` lstat mapping, `Commit.res:44,105`).

### Step 3: Tests

Commit message: `test(path): dir-symlink ancestor escape rejected; stat flag gone`

1. `test/PathTraversal_test.res` (model after `:96,:106`): create
   `outputDir/link` as a directory symlink pointing OUTSIDE the tree, then
   check `isWithinTree(outputDir/link/newfile, outputDir)` → must be `false`.
2. Same file: deep non-existent path under a REAL directory
   (`outputDir/a/b/c/newfile`, none existing) → must be `true` (no false
   positives — the critical regression guard).
3. `test/PathSecurity_test.res`: existing-leaf symlink case unchanged
   (realpath already resolved it before this change).
4. `test/NodeJsFileSystem_test.res`: stat result no longer exposes the flag;
   lstat still does.

**Verify**: `npx retest ./test/PathTraversal_test.res.mjs ./test/PathSecurity_test.res.mjs ./test/NodeJsFileSystem_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The four cases above. Real filesystem temp dirs are already the pattern in
  these test files (symlink creation via `fs.symlink` or the port equivalent —
  check how existing symlink tests at `test/Commit_test.res:270` create them
  and copy that).
- Full-suite gate (Commit/Phase2 suites exercise containment indirectly).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new traversal tests
- [ ] Dir-symlink + non-existent-leaf containment test exists and passes
- [ ] Deep non-existent path still passes containment (false-positive guard)
- [ ] `grep -rn "isSymbolicLink" src/` shows no stat-path sites
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Drift vs the excerpts above (since `0267337`).
- The file-system port exposes no `realpath` usable for the ancestor walk
  (report the actual port surface — do not bypass the port with a raw binding).
- The walk-up breaks ANY existing legitimate non-existent-path test after one
  fix attempt (false positives are worse than the hole — stop and report).
- The stat record type is shared with `lstat` in a way that makes removing the
  flag affect lstat (report the type structure).

## Maintenance notes

- TOCTOU note: containment-then-write is still not atomic; this plan closes
  the resolution gap, not the race. If blueprint ever runs concurrent
  generations, an openat2-style `RESOLVE_BENEATH` approach would be the real
  fix — out of scope.
- Reviewer should scrutinize: the ancestor walk must use the injected fs port
  (no direct `NodeJs.Fs` calls) to keep the ports discipline.
