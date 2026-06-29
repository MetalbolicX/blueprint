# Plan 015: Fix ScriptFile to use execFileAsync instead of shell interpretation

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat bfd0397..HEAD -- src/application/pipeline/ShellExecutor.res`
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

ScriptFile execution uses `shell.execAsync(resolvedPath, ~options=execOpts)` with `shell: true`, passing the resolved path as a command string to `child_process.exec`. If the resolved script path contains shell metacharacters (spaces, backticks, `$(...)`), the shell will interpret them. While `PathSecurity.isWithinTree` validates the path is within the project tree, a path like `my script.sh` would only execute `my` and ignore `script.sh`. A path containing `$(malicious)` would execute the subshell. Script files should be executed directly via `execFile`, not through a shell.

## Current state

- `src/application/pipeline/ShellExecutor.res:193-235` — ScriptFile branch:
  - Line 203-209: `execOpts` includes `shell: true`
  - Line 210: `shell.execAsync(resolvedPath, ~options=execOpts)` — passes path as command string through shell
- The `ToolCall` branch at lines 99-106 already uses `shell.execFileAsync(command, ~args, ~options=execFileOpts)` — the correct pattern exists in the same file.

## Commands you will need

| Purpose   | Command                              | Expected on success       |
|-----------|--------------------------------------|---------------------------|
| Build     | `pnpm res:build`                     | exit 0                    |
| Tests     | `pnpm res:test`                      | all pass                  |

## Scope

**In scope**:
- `src/application/pipeline/ShellExecutor.res` — change ScriptFile branch to use `execFileAsync`

**Out of scope**:
- Changes to `ExecPolicy.res` or execution policy logic
- Changes to `Hooks.res`
- Changes to InlineCommand or ToolCall branches

## Steps

### Step 1: Replace `shell.execAsync` with `shell.execFileAsync` for ScriptFile

In `src/application/pipeline/ShellExecutor.res`, in the ScriptFile branch (lines 203-210):

```rescript
// Before:
let execOpts: Ports.shellOptions = {
  cwd: cwd,
  env: safeEnv,
  shell: true,
  encoding: "utf8",
  timeout: ExecPolicy.defaultTimeout,
}
shell.execAsync(resolvedPath, ~options=execOpts)

// After:
let execFileOpts: Ports.shellOptions = {
  cwd: cwd,
  env: safeEnv,
  encoding: "utf8",
  timeout: ExecPolicy.defaultTimeout,
}
shell.execFileAsync(resolvedPath, ~options=execFileOpts)
```

Key changes:
1. Remove `shell: true` from options
2. Change `shell.execAsync(resolvedPath, ...)` to `shell.execFileAsync(resolvedPath, ...)`
3. Rename variable from `execOpts` to `execFileOpts` for consistency with the ToolCall branch

**Verify**: `pnpm res:build` → exits 0

### Step 2: Run full test suite

**Verify**: `pnpm res:test` → all tests pass

## Test plan

- No new tests required — existing `ShellExecutor_test.res` covers ScriptFile execution
- The change is behavioral (no shell interpretation) but existing tests should still pass since valid script paths don't contain shell metacharacters

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 (no regressions)
- [ ] `grep -n "shell.*true" src/application/pipeline/ShellExecutor.res` does NOT show `shell: true` in the ScriptFile branch
- [ ] `grep -n "execFileAsync" src/application/pipeline/ShellExecutor.res` shows the call in the ScriptFile branch
- [ ] No files outside in-scope list are modified

## STOP conditions

- The code at `ShellExecutor.res:193-235` doesn't match the described ScriptFile branch
- `pnpm res:build` fails after Step 1
- The fix requires touching files outside the in-scope list

## Maintenance notes

- The ToolCall branch (lines 99-106) already uses `execFileAsync` — this change aligns ScriptFile with the same pattern
- Script files from `_templates/` are resolved via `path.resolve` and validated by `PathSecurity.isWithinTree` before execution — the path validation remains intact
- Future work: InlineCommand still uses `execShellCommand` with shell interpretation — that's a separate concern (and currently dead code per audit finding SEC-10)
