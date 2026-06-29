# Plan 011: Add ShellExecutor unit tests

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/application/pipeline/ShellExecutor.res test/`
> If ShellExecutor.res changed significantly, read the current version and
> adjust test cases accordingly.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

ShellExecutor is a 247-line security boundary module that implements the
ExecPolicy decisions, environment variable filtering, fetch temp-file
cleanup, and shell command execution. It's currently tested only through
slow Phase2 integration tests (1073 lines) — the error paths have zero
dedicated coverage. A regression in the shell execution could silently
weaken the security posture that WS2/WS4 established.

## Current state

**File**: `src/application/pipeline/ShellExecutor.res` (247 lines)

Key function: `executeShellCommands` handles 4 command types:
- `Fetch(url)` — downloads content, writes to temp file
- `ToolCall({name, toolDef})` — runs configured tool via ExecPolicy
- `InlineCommand(command)` — runs command via shell with allowlist check
- `ScriptFile(cmdPath)` — runs script file with path-security check

Helper functions:
- `cleanupFetchTmpFiles(~tmpFiles, ~fs)` — removes temp files
- `buildEnvFilterConfig(shellEnv)` — builds env filter configuration

**Existing test patterns to follow**:
- `test/ExecPolicy_test.res` — mock ports, pattern-match on decisions
- `test/EnvFilter_test.res` — mock ports, assert dict contents
- `test/Phase2_test.res` (lines 1-50) — mock FS with injected failures

**Convention**: Test files use `suite("name", () => { test("desc", () => {...}) })`.
Mock ports are constructed as inline records.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**: 
- `test/ShellExecutor_test.res` — create

**Out of scope**:
- Changing ShellExecutor.res to make it testable (it's already testable via port injection)
- Integration tests in Phase2_test.res
- Deno adapters

## Steps

### Step 1: Create the test file

Create `test/ShellExecutor_test.res`. Import `TestHelpers`.

### Step 2: Test cleanupFetchTmpFiles

Test these cases:
- Empty list: returns `Ok(())` / resolves without error
- Single file: `fs.rm` called once
- Multiple files: `fs.rm` called for each
- File that fails to delete: error is silently swallowed (current behavior — the `Promise.catch` handles it)

Use a mock `Ports.fileSystem` that tracks `rm` calls in a mutable ref.

### Step 3: Test buildEnvFilterConfig

Test these cases:
- Empty config: returns config with empty vars array
- Config with vars: returns config with populated vars array

Model after `EnvFilter_test.res` patterns.

### Step 4: Test executeShellCommands — Fetch

Test these cases:
- Successful fetch: writes temp file, increments count
- Fetch failure: returns error
- Multiple fetches: each creates unique temp file

Mock `Fetcher.fetch` is tricky since it's a module-level call. Instead,
structure the test to inject a mock `shell` port and inspect calls.
The Fetch branch calls `Fetcher.fetch(url)` directly — to test this in
isolation, you'd need to either:
(a) Make `Fetcher.fetch` injectable, OR
(b) Test the downstream behavior (the write and count increment)

For now, focus on testing `cleanupFetchTmpFiles` (which doesn't depend on
Fetcher) and the ToolCall/InlineCommand branches (which go through ports).

### Step 5: Test executeShellCommands — ToolCall

Test these cases:
- ExecFile branch (args present): calls `shell.execFileAsync` with correct args
- ShellExact branch (no args + allowlist): calls `shell.execAsync` with shell:true
- Reject branch (no args + no allowlist): returns error with rejection message
- Timeout branch (result.killed): returns timeout error

### Step 6: Test executeShellCommands — InlineCommand

Test these cases:
- Shell disabled (`shellConfig.enabled = false`): returns error
- Command not in allowlist: returns error
- Command path outside project tree: returns error
- Successful execution: increments count

### Step 7: Test executeShellCommands — ScriptFile

Test these cases:
- Script path outside project tree: returns error
- Script file doesn't exist: returns error
- Successful execution: calls `shell.execAsync` with resolved path
- Timeout: returns timeout error

**Verify after each step**: `pnpm res:build` compiles; `pnpm res:test` passes
(though the new tests may fail until written).

### Final verification

```bash
pnpm res:build
pnpm res:test
```

All tests pass, including the new ShellExecutor tests.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; ShellExecutor tests exist and pass
- [ ] Tests cover at minimum: `cleanupFetchTmpFiles`, `buildEnvFilterConfig`,
      and the four command-type branches (Fetch, ToolCall, InlineCommand, ScriptFile)
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- `ShellExecutor.res` has been significantly refactored (check git diff against
  the planned-at SHA). If the function signatures or branch structure changed,
  stop and report.
- A test step requires modifying `ShellExecutor.res` to make a function
  injectable — stop and report the refactoring need.
- The `Fetcher.fetch` dependency blocks testing the Fetch branch (acceptable —
  test what you can; note the limitation).

## Maintenance notes

The Fetch branch is hard to unit test because it calls `Fetcher.fetch` directly
rather than through a port. If future refactoring makes shell command execution
go through a "command runner" abstraction, this test file should be updated.
For now, the error paths of the ToolCall, InlineCommand, and ScriptFile branches
are the highest-value targets — those are the security-critical paths.
