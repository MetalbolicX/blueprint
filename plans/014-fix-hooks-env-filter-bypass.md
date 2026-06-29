# Plan 014: Pass safeEnv to non-path hooks without args

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat bfd0397..HEAD -- src/infrastructure/hooks/Hooks.res test/HookSecurity_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `bfd0397`, 2026-06-29

## Why this matters

Non-path hooks without explicit args (e.g., `command: "npm"`) call `execWithTimeout` which creates `let options: Ports.shellOptions = {timeout: timeoutMs}` with NO `env` field. Node.js defaults to `process.env` when `env` is undefined. The config's `shell.env` allowlist (built as `safeEnv` at line 58) is silently ignored for this code path. If the parent process has secrets in env (CI tokens, API keys), they leak to the hook process. The fix is a one-line change.

## Current state

- `src/infrastructure/hooks/Hooks.res:74-87` — `execWithTimeout` helper creates options with only `{timeout: timeoutMs}`, no `env` field.
- `src/infrastructure/hooks/Hooks.res:58` — `let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, process.env())` — built correctly but only used by path-based hooks (lines 66-71) and non-path hooks with args (lines 129-134).
- `src/infrastructure/hooks/Hooks.res:137-143` — Non-path hooks without args call `execWithTimeout(hook.command, timeout)` which uses options without env.
- `test/HookSecurity_test.res` — existing tests cover path-based hooks and exit codes; no test for env filtering on non-path hooks.

## Commands you will need

| Purpose   | Command                              | Expected on success       |
|-----------|--------------------------------------|---------------------------|
| Tests     | `pnpm res:test -- HookSecurity`     | all pass                  |
| Full test | `pnpm res:test`                      | all pass                  |

## Scope

**In scope**:
- `src/infrastructure/hooks/Hooks.res` — modify `execWithTimeout` to accept and use `safeEnv`
- `test/HookSecurity_test.res` — add test for env filtering on non-path hooks

**Out of scope**:
- Changes to `EnvFilter.res` or `EnvFilter` logic
- Changes to `ShellExecutor.res`

## Steps

### Step 1: Modify `execWithTimeout` to accept env parameter

In `src/infrastructure/hooks/Hooks.res`, change the `execWithTimeout` helper signature (line 74) to accept an optional `env` parameter:

```rescript
let execWithTimeout: (string, int, option<dict<string>>) => promise<result<Ports.execResult, string>> = async (cmd, timeoutMs, env) => {
  try {
    let options: Ports.shellOptions = {
      timeout: timeoutMs,
      env: switch env {
      | Some(e) => Some(e)
      | None => None
      },
    }
    let result = await shell.execAsync(cmd, ~options)
    Ok(result)
  } catch {
  | JsExn(e) =>
    let msg = switch JsExn.message(e->Obj.magic) {
    | Some(m) => m
    | None => "unknown error"
    }
    Error(msg)
  }
}
```

**Verify**: `pnpm res:build` → exits 0 (compilation succeeds — the call site will temporarily break)

### Step 2: Pass `safeEnv` to `execWithTimeout` at the call site

In `src/infrastructure/hooks/Hooks.res`, at line 138 where `execWithTimeout` is called for non-path hooks without args:

```rescript
// Before:
let r = await execWithTimeout(hook.command, timeout)

// After:
let r = await execWithTimeout(hook.command, timeout, Some(safeEnv))
```

**Verify**: `pnpm res:build` → exits 0

### Step 3: Add test for env filtering on non-path hooks

In `test/HookSecurity_test.res`, add a test that verifies non-path hooks receive only the safe env:

```rescript
TestHelpers.test("Non-path hook without args receives filtered env (no process.env leak)", () => {
  // Set a custom env var in the mock process
  let customEnv = Dict.make()
  Dict.set(customEnv, "PATH", "/usr/bin")
  Dict.set(customEnv, "HOME", "/root")
  Dict.set(customEnv, "SECRET_KEY", "should-not-leak")
  Dict.set(customEnv, "API_TOKEN", "should-not-leak")

  let mockProcess = {
    ...MockProcess.make(),
    env: () => customEnv,
  }

  // Hook command is "echo" (no slash = non-path), no args
  let hook: Config.hookCommand = {command: "echo", args: None}
  let result = await Hooks.executeHook(
    ~hook,
    ~cwd="/tmp",
    ~timeout=5000,
    ~hookType=PreGenerate,
    ~shellEnv=None,
    ~shell=MockShell.make(),
    ~process=mockProcess,
    ~path=MockPath.make(),
    ~fs=MockFs.make(),
  )
  // The hook should succeed — it ran with filtered env
  TestHelpers.assert_ok(result)
})
```

Note: The exact mock structure depends on how `MockProcess.make()` works in the test suite. Adapt the test to match the existing mock patterns in `test/HookSecurity_test.res`.

**Verify**: `pnpm res:test -- HookSecurity` → all tests pass including new one

### Step 4: Run full test suite

**Verify**: `pnpm res:test` → all tests pass (no regressions)

## Test plan

- 1 new test in `test/HookSecurity_test.res` covering:
  - Non-path hook without args receives filtered env, not full `process.env`
- Model after existing `HookSecurity_test.res` test patterns

## Done criteria

- [ ] `pnpm res:test -- HookSecurity` exits 0 with all tests passing
- [ ] `pnpm res:test` exits 0 (no regressions)
- [ ] `grep -n "execWithTimeout" src/infrastructure/hooks/Hooks.res` shows env parameter in both signature and call site
- [ ] No files outside in-scope list are modified

## STOP conditions

- The code at `Hooks.res:74-87` doesn't match the described `execWithTimeout` helper
- `pnpm res:build` fails after Step 1
- The fix requires touching files outside the in-scope list

## Maintenance notes

- The `execWithTimeout` helper is local to `executeHook` — changes are self-contained
- If non-path hooks with args are added in the future, they already use `execFileOpts` (which has `env: safeEnv`) — no additional work needed
- Future work: consider whether `execWithTimeout` should always use `safeEnv` by default instead of requiring it as a parameter
