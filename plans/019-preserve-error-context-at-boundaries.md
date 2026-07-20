# Plan 019: Stop discarding error context at CLI and shell boundaries

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/interfaces/cli/Main.res src/application/pipeline/ShellExecutor.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

Two independent error-boundary problems produce bad diagnostics. First, `Main.res` has no rejection handler on the top-level async IIFE — on Node ≥15, an escaped promise rejection crashes with a raw stack trace instead of a clean error message. Second, three `Promise.catch(_ => ...)` blocks in `ShellExecutor.res` discard the original system error, so users see generic "Tool 'X' execution failed" with no root cause when a child process fails to spawn (e.g. ENOENT for missing binary, ENOMEM, permission denied). Both are cheap fixes that dramatically improve debuggability.

## Current state

- `src/interfaces/cli/Main.res` — the entire file (2 lines):
  ```rescript
  // CLI entry point — invoked by Node when dist/main.mjs runs
  (async () => { await Cli.main() })()->ignore
  ```
  The `->ignore` discards the promise. If `Cli.main()` rejects, the rejection is unhandled. On Node ≥15 this triggers the `unhandledRejection` event and (depending on Node flags) crashes with a raw stack trace.

- `src/application/pipeline/ShellExecutor.res` — three `Promise.catch` blocks that discard the error:
  ```rescript
  // ShellExecutor.res:69 — Fetch write failure (discard original error)
  })->Promise.catch(_ => {
    Promise.resolve(Error("Failed to write fetched content: " ++ url))
  })
  ```
  ```rescript
  // ShellExecutor.res:109 — ExecFile failure (discard original error)
  })->Promise.catch(_ => {
    Promise.resolve(Error("Tool '" ++ name ++ "' execution failed"))
  })
  ```
  ```rescript
  // ShellExecutor.res:135 — ExecAsync/ShellExact failure (discard original error)
  })->Promise.catch(_ => {
    Promise.resolve(Error("Tool '" ++ name ++ "' execution failed"))
  })
  ```

  Note: The ScriptFile catch at line 212-219 **already extracts the error message correctly**:
  ```rescript
  // ShellExecutor.res:212-219 — ScriptFile (already correct, out of scope)
  })->Promise.catch(e => {
    let msg = switch JsExn.message(e->Obj.magic) {
    | Some(m) => m
    | None => "unknown"
    }
    Promise.resolve(Error("Script execution failed: " ++ msg ++ " (" ++ cmdPath ++ ")"))
  })
  ```
  This is the pattern to follow — it uses `Obj.magic` to bridge from `exn` to `JsExn.t` for message extraction. This is an accepted idiom in this codebase (the `Promise.catch` handler receives `exn`, not `JsExn.t`, so `Obj.magic` is the bridge).

- Repo conventions: Conventional commits, PascalCase modules, snake_case values. The `Obj.magic` bridge from `exn` to `JsExn.t` is an established pattern in this codebase (used at ShellExecutor.res:215). No other safe helper for extracting JS exception messages from `exn` exists in the codebase.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm build`             | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope** (the only files you should modify):
- `src/interfaces/cli/Main.res` — add `.catch` handler for unhandled rejections
- `src/application/pipeline/ShellExecutor.res` — capture error messages in the three catch blocks (lines 69, 109, 135)
- `test/ShellExecutor_test.res` — add tests verifying error messages are surfaced

**Out of scope**:
- `src/application/pipeline/ShellExecutor.res:212-219` — the ScriptFile catch already extracts messages correctly
- `src/interfaces/cli/Cli.res` — the `Cli.main()` function; its internal error handling is separate
- Any changes to `Ports.shell` or `Ports.shellOptions` types

## Git workflow

- Branch: `advisor/019-preserve-error-context-boundaries`
- Commit per step or per logical unit; message style: conventional commits, e.g. `fix(main): add rejection handler to top-level async`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Add rejection handler to Main.res

In `src/interfaces/cli/Main.res`, replace the entire file content:

```rescript
// BEFORE (2 lines):
// CLI entry point — invoked by Node when dist/main.mjs runs
(async () => { await Cli.main() })()->ignore

// AFTER:
// CLI entry point — invoked by Node when dist/main.mjs runs
(async () => {
  await Cli.main()
})->Promise.catch(e => {
  let msg = switch JsExn.message(e->Obj.magic) {
  | Some(m) => m
  | None => "unknown error"
  }
  Console.error("Fatal: " ++ msg)
  process->exit(1)
})->ignore
```

Note: `process` is available as a Node.js global in the ReScript/Node environment. If the codebase imports it differently, check how `Ports.process` is used — but `Main.res` is the entrypoint and runs in Node context directly.

**Verify**: `pnpm build` → exit 0

### Step 2: Fix ShellExecutor.res line 69 — Fetch write failure

In `src/application/pipeline/ShellExecutor.res`, at line 69, replace:

```rescript
// BEFORE:
})->Promise.catch(_ => {
  Promise.resolve(Error("Failed to write fetched content: " ++ url))
})

// AFTER:
})->Promise.catch(e => {
  let msg = switch JsExn.message(e->Obj.magic) {
  | Some(m) => m
  | None => "unknown error"
  }
  Promise.resolve(Error("Failed to write fetched content: " ++ url ++ " — " ++ msg))
})
```

**Verify**: `pnpm build` → exit 0

### Step 3: Fix ShellExecutor.res line 109 — ExecFile failure

In `src/application/pipeline/ShellExecutor.res`, at line 109, replace:

```rescript
// BEFORE:
})->Promise.catch(_ => {
  Promise.resolve(Error("Tool '" ++ name ++ "' execution failed"))
})

// AFTER:
})->Promise.catch(e => {
  let msg = switch JsExn.message(e->Obj.magic) {
  | Some(m) => m
  | None => "unknown error"
  }
  Promise.resolve(Error("Tool '" ++ name ++ "' execution failed: " ++ msg))
})
```

**Verify**: `pnpm build` → exit 0

### Step 4: Fix ShellExecutor.res line 135 — ShellExact failure

In `src/application/pipeline/ShellExecutor.res`, at line 135, replace:

```rescript
// BEFORE:
})->Promise.catch(_ => {
  Promise.resolve(Error("Tool '" ++ name ++ "' execution failed"))
})

// AFTER:
})->Promise.catch(e => {
  let msg = switch JsExn.message(e->Obj.magic) {
  | Some(m) => m
  | None => "unknown error"
  }
  Promise.resolve(Error("Tool '" ++ name ++ "' execution failed: " ++ msg))
})
```

**Verify**: `pnpm build` → exit 0

### Step 5: Add tests to ShellExecutor_test.res

In `test/ShellExecutor_test.res`, add tests after the existing ToolCall suite (after line 396) to verify that Promise.catch errors surface the message:

```rescript
// ---------- executeShellCommands — error message surfacing ----------

suite("ShellExecutor.executeShellCommands — error message surfacing", () => {
  testAsync("ExecFile rejection surfaces error message", resolve => {
    let rejectMsg: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)
    let shell: Ports.shell = {
      ...makeShell(),
      execFileAsync: (_cmd, ~args as _=?, ~options as _=?) => rejectMsg("spawn ENOENT"),
    }
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "missing",
          toolDef: {
            name: "missing",
            command: "missing-binary",
            args: [],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true})
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) =>
        // Should contain the original error, not just "execution failed"
        assert_true(String.includes(msg, "execution failed"))
        assert_true(String.includes(msg, "ENOENT"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("ShellExact rejection surfaces error message", resolve => {
    let rejectMsg: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)
    let shell: Ports.shell = {
      ...makeShell(),
      execAsync: (_cmd, ~options as _=?) => rejectMsg("spawn EACCES"),
    }
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "denied",
          toolDef: {
            name: "denied",
            command: "restricted",
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "denied", command: "restricted"}],
    })
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) =>
        assert_true(String.includes(msg, "execution failed"))
        assert_true(String.includes(msg, "EACCES"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
```

**Verify**: `pnpm res:test -- ShellExecutor` → all tests pass including 2 new ones

### Step 6: Run full test suite

**Verify**: `pnpm res:test` → all tests pass (no regressions)

## Test plan

- 2 new tests in `test/ShellExecutor_test.res`:
  - ExecFile rejection surfaces ENOENT in error message
  - ShellExact rejection surfaces EACCES in error message
- Model after existing `test/ShellExecutor_test.res` test structure (same mocks, `suite`/`testAsync` pattern)
- Verification: `pnpm res:test` → all pass, including 2 new tests

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0; 2 new tests exist and pass
- [ ] `grep -rn "Promise.catch(_ =>" src/application/pipeline/ShellExecutor.res` returns no matches at lines 69, 109, 135 (the three catch blocks now capture `e`)
- [ ] `src/interfaces/cli/Main.res` contains a `Promise.catch` handler (not just `->ignore`)
- [ ] No files outside the in-scope list are modified (`git status`)

## STOP conditions

- The code at `ShellExecutor.res:69`, `:109`, or `:135` doesn't match the described `Promise.catch(_ => ...)` patterns
- The code at `Main.res` is more than 2 lines (the file has drifted)
- `Obj.magic(e->Obj.magic)` double-bridge is needed (the `Promise.catch` handler type is `exn`, and `Obj.magic` bridges to `JsExn.t`; if the first `Obj.magic` already returns `JsExn.t`, remove the outer bridge)
- `process` global is not available in `Main.res` scope — check how the codebase accesses it (may need `NodeJsProcess` or similar)
- `pnpm build` fails after Step 1 and the fix isn't obvious after one attempt

## Maintenance notes

- The `Obj.magic` bridge from `exn` to `JsExn.t` is an established pattern in this codebase (see ShellExecutor.res:215). If a safer helper is added in the future, all three catch blocks plus Main.res should migrate.
- If `Cli.main()` adds its own error handling in the future, the Main.res catch may become redundant — but it's still the right safety net for errors that escape `Cli.main()`.
- The ScriptFile catch at ShellExecutor.res:212-219 already does this correctly — it's the reference implementation for the pattern used in Steps 2-4.
