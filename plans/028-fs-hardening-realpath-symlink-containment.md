# Plan 028: Harden filesystem containment (realpath catch-all, symlink follow, self-contained checks)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat c29f1c9..HEAD -- src/infrastructure/path/PathSecurity.res src/application/pipeline/Staging.res src/application/pipeline/Commit.res src/domain/ports/Ports.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `c29f1c9`, 2026-08-01
- **Method**: TDD — each step writes a failing test that proves the hole, then implements until green.

## Why this matters

The codebase defends path traversal via `PathSecurity.isWithinTree` at every output
boundary — but the defense has three gaps that are bypassable without a malformed
template: (1) `_resolveRealPath` swallows **all** errors, not just ENOENT, so an
`EACCES`/`ELOOP` on a symlink silently degrades the symlink check to a symbolic-path
prefix match; (2) `fs.cp` in Commit follows the *source* symlink, so a symlink planted
in staging copies an arbitrary file's contents into output; (3) `Staging.writeStagedFile`
and `Commit.rollbackOutput` trust their callers to have validated containment, so a
future caller can write/delete outside scope with no compiler help. These are the
highest-leverage, fully testable hardening wins in the security audit.

## Current state

All line numbers verified against commit `c29f1c9`.

- `src/infrastructure/path/PathSecurity.res` — path-traversal guard:
  - Lines 8-14 — `_resolveRealPath` catches everything:
    ```
    8: let _resolveRealPath: (string, Ports.fileSystem) => promise<string> = async (path, fs) => {
    9:   try {
    10:    await fs.realpath(path)
    11:  } catch {
    12:  | _ => path          // <-- catches EACCES, ELOOP, ... not just ENOENT
    13:  }
    14: }
    ```
  - Lines 29-30 — both path and root resolve through it; line 49 returns the prefix-boundary check on the (possibly unresolved) result.
- `src/application/pipeline/Commit.res`:
  - Line 41 — `backupIfOverwriting`: `await fs.cp(destPath, backupPath, ~options={recursive: false})` (follows source symlink).
  - Line 93 — `commitFiles`: `await fs.cp(stagedPath, destPath, ~options={recursive: false})` (follows source symlink).
  - Lines 143-161 — `rollbackOutput` iterates `committedFiles` doing `fs.cp`/`fs.rm` with **no** `isWithinTree` re-check.
  - Lines 191-203 — `rollback` does `fs.rm(stagingDir, ~options={recursive: true})` with no temp-dir assertion.
- `src/application/pipeline/Staging.res`:
  - Lines 34-38 — `writeStagedFile` does `path.join(stagingDir, targetPath)` then `mkdir`+`writeFile` with **no** containment check.
- `src/domain/ports/Ports.res`:
  - Lines 29-40 — `fileSystem` port. It has `stat` (follows symlinks) but **no `lstat`** (grep confirms `lstat` appears nowhere in `src/`). Step 5 adds it.

**Repo conventions**:
- Result/error handling follows the `result<'a, string>` pattern — see `Staging.res:21-48` and `Manifest.res:200-213`. Match it.
- Filesystem errors are caught via `JsExn(obj)` and the `.code` read via `Obj.magic(obj)["code"]` — see `TemplateRenderer.res:95-108` for the exact pattern (ENOENT branch vs real-error branch). Reuse it in Step 1.
- Tests live in `test/`, run via `pnpm res:test` (retest). Existing exemplar: `test/PathSecurity_test.res` — it builds a mock `fileSystem` (lines 9-20) and runs the suite under both Node and Deno adapters (lines 114-115), plus a real-fs symlink test (lines 117-153). Model new tests on this file.

## Commands you will need

| Purpose   | Command                          | Expected on success |
|-----------|----------------------------------|---------------------|
| Compile   | `pnpm res:build`                 | exit 0, no errors   |
| Tests     | `pnpm res:test`                  | all pass            |
| Focused   | `npx retest ./test/PathSecurity_test.res.mjs` | all pass |
| Coverage  | `pnpm res:test:coverage`         | exits 0 (≥50% lines/functions, ≥40% branches) |

## Scope

**In scope**:
- `src/infrastructure/path/PathSecurity.res` (Step 1)
- `src/application/pipeline/Staging.res` (Step 2)
- `src/application/pipeline/Commit.res` (Steps 2, 3, 4)
- `src/domain/ports/Ports.res` (Step 5 — add `lstat`)
- `src/infrastructure/adapters/NodeJsFileSystem.res` and `DenoFileSystem.res` (Step 5 — implement `lstat`)
- `test/PathSecurity_test.res` and a new `test/Staging_test.res` / `test/Commit_test.res` (or extend existing) for the new tests
- Every mock `fileSystem` in `test/` must be updated to include the new `lstat` field after Step 5 (the compiler will list them).

**Out of scope**:
- Any change to the *public* pipeline behavior (no new error messages surfaced to users beyond "outside tree" / "symlink").
- The `Obj.magic` casts at EJS boundaries — that is a separate concern (previously rejected as QUAL-11).
- Shell execution policy (`ExecPolicy`, `ShellExecutor`) — covered by existing plans 014/015.

## Steps

### Step 1: Narrow the realpath catch-all to ENOENT/ENOTDIR (TDD)

1. **Write the failing test** in `test/PathSecurity_test.res`: add a mock `fileSystem` whose `realpath` rejects with a non-ENOENT code (e.g. `EACCES`). Assert `PathSecurity.isWithinTree(<inside prefix>, <root>, adapter, mockFs)` resolves to `false` (deny on resolution failure). Today it resolves to `true` because the unresolved path still satisfies the prefix check. Use `testAsync` + `Promise.catch` like the existing tests (lines 24-33).
2. **Make `_resolveRealPath` return `result<string, string>`** (not `promise<string>`): on `JsExn(obj)`, read `Obj.magic(obj)["code"]` (pattern from `TemplateRenderer.res:100-103`); for `Some("ENOENT")` or `Some("ENOTDIR")` return `Ok(path)` (file doesn't exist yet — correct), for anything else return `Error("realpath failed for " ++ path ++ ": " ++ code-or-msg)`.
3. **Update `isWithinTree`**: resolve both via the new result type; if either is `Error`, `Promise.resolve(false)` (deny). Otherwise run the existing `isBoundary` prefix check (lines 36-47) on the two resolved strings.
4. **Verify**: `npx retest ./test/PathSecurity_test.res.mjs` → the new test passes and all existing 10+ cases still pass. `pnpm res:build` → exit 0.

### Step 2: Self-contained containment in Staging.writeStagedFile (TDD)

1. **Write the failing test**: with a mock `fileSystem` whose `realpath` is identity, call `Staging.writeStagedFile(~stagingDir="/tmp/s", ~targetPath="../../etc/evil", ...)` and assert it returns `Error(...)` and that `writeFile` was **never** called. (You may need to record calls in the mock.) Today it writes outside staging.
2. **Add the check** at `Staging.res:34`, before `mkdir`/`writeFile`:
   ```
   let stagedPath = path.join(stagingDir, targetPath)
   let isWithin = await PathSecurity.isWithinTree(stagedPath, stagingDir, path, fs)
   if !isWithin { Error("Staged path escapes staging directory: " ++ targetPath) } else { ...existing... }
   ```
3. **Verify**: new test passes; `pnpm res:build` exit 0; `pnpm res:test` green.

### Step 3: Re-validate containment in Commit.rollbackOutput (TDD)

1. **Write the failing test**: call `Commit.rollbackOutput(~committedFiles=["/etc/evil"], ~backups=[], ~fs=mockFs)` and assert it returns `Error` (a `rollbackFailure`) rather than `rm`-ing `/etc/evil`. Record `rm` calls in the mock to prove it was not invoked. Today it deletes.
2. **Add a per-item guard** in the `workItems` map (`Commit.res:143`): before the `cp`/`rm`, call `PathSecurity.isWithinTree(outputPath, <outputDir>, ...)`. **Note**: `rollbackOutput` currently takes no `outputDir`/`path` args — add `~outputDir: string` and `~path: Ports.path` to its signature and update the caller(s) in `Phase2.res`. Grep `rollbackOutput` to find all callers.
3. **Verify**: new test passes; `pnpm res:build` exit 0; `pnpm res:test` green.

### Step 4: Assert staging dir is within tmpdir before recursive rm (TDD)

1. **Write the failing test**: call `Commit.rollback("/usr", ~fs=mockFs)` (or a path outside tmpdir) and assert it returns `Error` and `rm` was not called.
2. **Add the guard** at `Commit.res:192`, before `fs.rm(stagingDir, ~options={recursive: true})`: compute the tmpdir root (the caller already has the staging prefix; pass `~tmpRoot: string` into `rollback`, sourced from `EngineLifecycle`'s `os.tmpdir()`) and assert `PathSecurity.isWithinTree(stagingDir, tmpRoot, path, fs)`; on `false`, `Error("Refusing to remove staging dir outside temp directory: " ++ stagingDir)`.
3. **Verify**: new test passes; `pnpm res:test` green.

### Step 5: Reject source symlinks in fs.cp via lstat (TDD)

1. **Extend the port**: add `lstat: string => promise<statResult>` to `Ports.fileSystem` (`Ports.res:29-40`). The compiler will then error on every adapter and mock — that's the work list.
2. **Implement `lstat`** in `NodeJsFileSystem.res` (bind `fs.lstat`, returns `{isDirectory, isFile}` — but also expose `isSymbolicLink`; extend `Ports.statResult` at line 18 with `isSymbolicLink: unit => bool`) and `DenoFileSystem.res` (`Deno.lstatSync`). Add `lstat` to every mock in `test/` (return `isSymbolicLink: () => false` by default).
3. **Write the failing test**: a real-fs integration test (model on `PathSecurity_test.res:117-153`) — create a staging dir, plant a symlink `staged -> /etc/passwd`, run the commit path, assert the commit **rejects** the symlink rather than copying `/etc/passwd` into output.
4. **Add the guard** before both `fs.cp` calls (`Commit.res:41` and `:93`): `let st = await fs.lstat(src); if st.isSymbolicLink() { Error("Refusing to copy symbolic link: " ++ src) } else { ...cp... }`.
5. **Verify**: new test passes; `pnpm res:build` exit 0; `pnpm res:test` green; `pnpm res:test:coverage` meets gate.

## Test plan

- `test/PathSecurity_test.res`: +1 case (EACCES realpath → deny). All existing cases unchanged.
- New `test/Staging_test.res` (or extend a Commit test file): traversal `targetPath` rejected, `writeFile` not called.
- New/extended `test/Commit_test.res`: rollbackOutput rejects out-of-tree path; rollback rejects non-tmpdir path; commit rejects source symlink.
- Pattern to model on: `test/PathSecurity_test.res` (mock `fileSystem` at lines 9-20, `testAsync`+`Promise.catch` shape, real-fs symlink test at 117-153).
- Verification: `pnpm res:test` → all pass including the new cases.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; new tests for realpath-deny, staging containment, rollback containment, tmpdir assertion, and symlink rejection exist and pass
- [ ] `rg "catch \{ \| _ => path \}" src/infrastructure/path/PathSecurity.res` returns no matches
- [ ] `rg "fs.cp" src/application/pipeline/Commit.res` shows every `cp` preceded by an `lstat`/symlink check
- [ ] `lstat` present in `Ports.fileSystem` and both adapters
- [ ] No files outside the in-scope list are modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- `rollbackOutput` or `rollback` have gained additional callers since `c29f1c9` that pass unvalidated paths by design — do not silently change their contract; report.
- Adding `lstat` to the port breaks more than the two adapters + test mocks (e.g. a third adapter or a persisted mock) — report the full compiler work list rather than touching unplanned files.
- Any existing test starts failing for a reason other than the intended behavior change (Step 1 narrows the catch-all; a test that relied on an `EACCES` realpath *passing* would now correctly fail — if so, confirm that test encoded a real requirement and report it).
- The real-fs symlink integration test cannot run in the CI environment (no symlink permission) — report and convert to a mock-based test using a mock `lstat` that returns `isSymbolicLink: () => true`.

## Maintenance notes

- After Step 1, "realpath fails on a non-ENOENT error" is now a hard denial, not a silent fallback. Any future feature that needs realpath to tolerate permission errors must do so explicitly at the call site, not in `_resolveRealPath`.
- After Step 5, the `fileSystem` port gained `lstat` + `isSymbolicLink` on `statResult` — any new adapter must implement them. Document in `Ports.res` header comment.
- A reviewer should scrutinize: (a) that Step 1's deny-on-error default doesn't reject legitimate new-file creation (ENOENT still falls back correctly), and (b) that Step 3's new `rollbackOutput` signature is wired correctly in every caller.
