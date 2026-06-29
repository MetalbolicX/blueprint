# Plan 016: Write fetch temp files to staging directory instead of output directory

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat bfd0397..HEAD -- src/application/pipeline/ShellExecutor.res src/application/pipeline/Phase2.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `bfd0397`, 2026-06-29

## Why this matters

Fetch temp files are written to `outputDir` (the production output tree) at `ShellExecutor.res:75`. If the process crashes between the fetch write and the cleanup at line 241, a `fetch-{hash}.tmp` file persists in the output directory. The filename is deterministic (hash of the URL), so an attacker can predict it. This breaks the atomic commit guarantee — partial state leaks to the output directory. Writing to the staging directory instead ensures temp files are cleaned up by the normal rollback mechanism.

## Current state

- `src/application/pipeline/ShellExecutor.res:75` — `let fetchPath = path.join(cwd, fetchFileName)` where `cwd` is the output directory (passed from `Phase2.run`).
- `src/application/pipeline/ShellExecutor.res:241` — `cleanupFetchTmpFiles(tmpFiles, ~fs)` cleans up after execution.
- `src/application/pipeline/Phase2.res:85` — calls `ShellExecutor.executeShellCommands` with `~cwd=outputDir`.
- The `executeShellCommands` function signature takes `~cwd: string` which is the output directory.

## Commands you will need

| Purpose   | Command                              | Expected on success       |
|-----------|--------------------------------------|---------------------------|
| Build     | `pnpm res:build`                     | exit 0                    |
| Tests     | `pnpm res:test`                      | all pass                  |

## Scope

**In scope**:
- `src/application/pipeline/ShellExecutor.res` — add `~stagingDir` parameter, write fetch temp files there
- `src/application/pipeline/Phase2.res` — pass `stagingDir` to `ShellExecutor.executeShellCommands`

**Out of scope**:
- Changes to `Phase1.res` or staging directory creation logic
- Changes to `Fetcher.res` or fetch logic

## Steps

### Step 1: Add `~stagingDir` parameter to `executeShellCommands`

In `src/application/pipeline/ShellExecutor.res`, add `~stagingDir: string` to the function signature (line 25):

```rescript
let executeShellCommands: (
  ~commands: array<shellCommand>,
  ~cwd: string,
  ~stagingDir: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
) => promise<result<(int, array<string>), string>> = (
  ~commands,
  ~cwd,
  ~stagingDir,
  ~shellConfig,
  ~fs,
  ~path,
  ~process,
  ~shell,
) => {
```

**Verify**: `pnpm res:build` → will fail (call site in Phase2.res not yet updated) — this is expected

### Step 2: Write fetch temp files to `stagingDir` instead of `cwd`

In `src/application/pipeline/ShellExecutor.res`, change line 75:

```rescript
// Before:
let fetchPath = path.join(cwd, fetchFileName)

// After:
let fetchPath = path.join(stagingDir, fetchFileName)
```

**Verify**: `pnpm res:build` → will still fail (Phase2.res not yet updated)

### Step 3: Update Phase2.res call site to pass `stagingDir`

In `src/application/pipeline/Phase2.res`, find where `ShellExecutor.executeShellCommands` is called and add the `~stagingDir` parameter. The staging directory is already available in `Phase2.run` (it's the temp directory created for this generation run).

Look for the call to `ShellExecutor.executeShellCommands` and add `~stagingDir=stagingDir` (or whatever the staging directory variable is named in Phase2).

**Verify**: `pnpm res:build` → exits 0

### Step 4: Run full test suite

**Verify**: `pnpm res:test` → all tests pass

## Test plan

- No new tests required — existing `ShellExecutor_test.res` covers fetch execution
- The change is a path redirection; existing tests should still pass since they mock the filesystem

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 (no regressions)
- [ ] `grep -n "stagingDir" src/application/pipeline/ShellExecutor.res` shows the parameter and usage
- [ ] `grep -n "stagingDir" src/application/pipeline/Phase2.res` shows the parameter being passed
- [ ] `grep -n "fetchPath.*cwd" src/application/pipeline/ShellExecutor.res` returns no matches (old pattern removed)
- [ ] No files outside in-scope list are modified

## STOP conditions

- The code at `ShellExecutor.res:75` or `Phase2.res:85` doesn't match the described state
- `pnpm res:build` fails after Step 3
- The fix requires touching files outside the in-scope list
- The staging directory variable name in Phase2.res is unclear (STOP and report the actual variable name)

## Maintenance notes

- The staging directory is created by Phase1 and cleaned up by Phase2 rollback — fetch temp files will automatically be cleaned up by the existing rollback mechanism
- If the staging directory path changes in Phase1, this code follows automatically since it receives the path as a parameter
- The `cleanupFetchTmpFiles` call at line 241 still runs but becomes redundant (staging dir cleanup handles it). Consider removing it in a follow-up.
