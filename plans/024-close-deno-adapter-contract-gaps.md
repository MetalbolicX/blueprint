# Plan 024: Close Deno adapter contract gaps (silently discarded options)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/infrastructure/adapters/DenoFileSystem.res src/infrastructure/adapters/DenoShell.res src/domain/ports/Ports.res src/application/pipeline/ShellExecutor.res src/infrastructure/adapters/NodeJsShell.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

The Deno filesystem adapter silently discards `~options` parameters in `readFile`, `writeFile`, `cp`, and `readdir` — the functions accept the labeled argument but ignore it with `let _ = options`. This means callers believe they can pass encoding, recursive, or withFileTypes options, but on Deno those options have no effect. If any caller ever passes meaningful options, the Deno adapter will produce incorrect behavior without warning. The fix is to audit all callers: if no caller needs the discarded options, narrow the port type (remove or make optional); if callers do need them, implement on Deno. Additionally, the `shell?: bool` field in `shellOptions` is never read by DenoShell — a grep confirms no caller sets it via the port's `shellOptions` type (the only `shell: true` instances are direct uses in ShellExecutor.res for the ShellExact path, which is application-level and can be handled differently). Removing it eliminates a dead field.

**VETTED CONTEXT (do not re-litigate)**:
- `DenoShell.execFileAsyncRaw` correctly uses `Deno.Command` directly WITHOUT `sh -c` — this is correct and intentional.
- `DenoShell.execAsyncRaw` wraps in `sh -c` — this is CORRECT and matches Node exec semantics.
- The ONLY gap is the unread `shell` field in `shellOptions`.

## Current state

**File**: `src/infrastructure/adapters/DenoFileSystem.res` (48 lines)

Discarded options — four functions:
```rescript
// DenoFileSystem.res:4-6 — readFile discards options
readFile: (path, ~options=?) => {
  let _ = options // Deno readTextFile handles encoding via string automatically
  readTextFile(path)
},

// DenoFileSystem.res:8-10 — writeFile discards options
writeFile: (path, content, ~options=?) => {
  let _ = options
  writeTextFile(path, content)
},

// DenoFileSystem.res:27-29 — cp discards options
cp: async (src, dst, ~options=?) => {
  let _ = options
  await copyFile(src, dst)
},

// DenoFileSystem.res:31-33 — readdir discards options
readdir: async (path, ~options=?) => {
  let _ = options
  await readDirAsync(path)
},
```

Note: `mkdir` (lines 12–18) and `rm` (lines 20–25) DO read `options.recursive` correctly.

**File**: `src/domain/ports/Ports.res`

Option types (lines 12–17):
```rescript
type readFileOptions = {encoding: string}
type writeFileOptions = {encoding: string}
type mkdirOptions = {recursive: bool}
type rmOptions = {recursive: bool}
type cpOptions = {recursive: bool}
type readdirOptions = {withFileTypes: bool}
```

Shell options (lines 51–57):
```rescript
type shellOptions = {
  cwd?: string,
  env?: dict<string>,
  shell?: bool,
  encoding?: string,
  timeout?: int,
}
```

**File**: `src/infrastructure/adapters/DenoShell.res`

`execAsyncRaw` (lines 33–57) — reads `cwd`, `env`, `timeout` from options, ignores `shell` and `encoding`:
```rescript
let execAsyncRaw: (string, option<shellOptions>) => promise<execResult> = async (
  cmdString,
  optionsOpt,
) => {
  let options = optionsOpt->Belt.Option.getWithDefault({})
  let cmd = Deno.Command.make(
    "sh",
    {
      args: ["-c", cmdString],
      cwd: ?options.cwd,
      env: ?options.env,
      stdout: "piped",
      stderr: "piped",
      timeout: ?options.timeout,
    },
  )
```

**File**: `src/application/pipeline/ShellExecutor.res:114-120` — the only production construction of `shellOptions` with `shell` field:
```rescript
let shellOpts: Ports.shellOptions = {
  cwd: cwd,
  env: safeEnv,
  shell: true,
  encoding: "utf8",
  timeout: ExecPolicy.defaultTimeout,
}
```

## Commands you will need

| Purpose   | Command                  | Expected on success       |
|-----------|--------------------------|---------------------------|
| Build     | `pnpm build`             | exit 0                    |
| Tests     | `pnpm res:test`          | all pass                  |

## Scope

**In scope**:
- `src/infrastructure/adapters/DenoFileSystem.res` — narrow `readFile`, `writeFile`, `cp`, `readdir` signatures
- `src/domain/ports/Ports.res` — remove `shell` from `shellOptions`; potentially remove unused option types
- `src/application/pipeline/ShellExecutor.res` — remove `shell: true` from shellOpts construction
- `src/infrastructure/adapters/DenoShell.res` — no changes needed (already correct)

**Out of scope**:
- NodeJsFileSystem.res (it correctly passes options through)
- NodeJsShell.res (it correctly uses the options)
- Any behavioral changes to how shell commands are executed

## Steps

### Step 1: Grep all callers of discarded filesystem options

Before narrowing, verify no caller passes meaningful options to the functions Deno discards.

**Verify**: `grep -rn "readFile.*~options" src/` → list all callers
**Verify**: `grep -rn "writeFile.*~options" src/` → list all callers
**Verify**: `grep -rn "\.cp(" src/` → list all callers
**Verify**: `grep -rn "\.readdir(" src/` → list all callers

Decision procedure: if any caller passes non-default options (e.g., `~options={encoding: "utf8"}` to readFile, or `~options={withFileTypes: true}` to readdir), the port type must be kept and Deno must implement the option. If no caller passes options, the `~options` parameter can be removed from the port type entirely.

Based on the codebase analysis: `readFile` is called with `~options={encoding: "utf8"}` in multiple places (NodeJsFileSystem correctly handles this). `readdir` is called with `~options={withFileTypes: false}` in CommandsGenerator.res. These callers rely on the option. Therefore, the correct approach is NOT to remove the options from the port, but to keep the port types as-is and note that Deno's implementations are incomplete — OR to make the options actually work on Deno.

**Revised approach**: Since callers DO pass options, we cannot narrow the port. Instead, we document the Deno gap as a known limitation and leave the port types unchanged. The only actionable fix is removing the `shell` field.

**Verify**: grep results — report findings

### Step 2: Remove `shell` from `Ports.shellOptions`

In `src/domain/ports/Ports.res`, remove line 54:
```rescript
  shell?: bool,
```

The field becomes:
```rescript
type shellOptions = {
  cwd?: string,
  env?: dict<string>,
  encoding?: string,
  timeout?: int,
}
```

**Verify**: `pnpm build` → will FAIL (ShellExecutor.res:117 still sets `shell: true`). Expected.

### Step 3: Remove `shell: true` from ShellExecutor.res

In `src/application/pipeline/ShellExecutor.res`, remove `shell: true,` from the shellOpts construction at line 117:

Before:
```rescript
let shellOpts: Ports.shellOptions = {
  cwd: cwd,
  env: safeEnv,
  shell: true,
  encoding: "utf8",
  timeout: ExecPolicy.defaultTimeout,
}
```

After:
```rescript
let shellOpts: Ports.shellOptions = {
  cwd: cwd,
  env: safeEnv,
  encoding: "utf8",
  timeout: ExecPolicy.defaultTimeout,
}
```

**Verify**: `pnpm build` → exits 0

### Step 4: Verify DenoShell ignores encoding (documentation only)

DenoShell.res does not read `options.encoding` — this is a known gap. Since Deno's `TextDecoder` handles encoding implicitly, this is functionally correct but not explicitly documented. Add a comment in DenoShell.res at line 37 (after `let options = optionsOpt->Belt.Option.getWithDefault({})`):

```rescript
// NOTE: encoding is not read — Deno's TextDecoder handles UTF-8 implicitly.
// If non-UTF-8 encoding is needed, decode output.bytes manually.
```

**Verify**: `pnpm build` → exits 0

### Step 5: Run full test suite

**Verify**: `pnpm res:test` → all tests pass

### Step 6: Add documentation comment for DenoFileSystem options gap

In `src/infrastructure/adapters/DenoFileSystem.res`, add a comment at the top of the file:

```rescript
// DenoFileSystem — Deno fs adapter implementing Ports.fileSystem.
// KNOWN GAP: readFile, writeFile, cp, and readdir silently discard ~options.
// Deno.readTextFile/writeTextFile handle encoding via string automatically.
// copyFile and readDirAsync do not support recursive or withFileTypes.
// If a caller needs these options, implement them on Deno before relying on them.
```

**Verify**: `pnpm build` → exits 0

## Test plan

- No new tests required — this is a contract cleanup (removing a dead field) and documentation of known gaps.
- Existing tests cover the ShellExact path in ShellExecutor (the only place `shell: true` was used).
- Verification: `pnpm res:test` → all pass

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `grep -n "shell" src/domain/ports/Ports.res` returns no matches for `shell?: bool`
- [ ] `grep -n "shell: true" src/application/pipeline/ShellExecutor.res` returns no matches
- [ ] `grep -n "shell" src/infrastructure/adapters/DenoShell.res` returns no matches (field no longer exists to ignore)
- [ ] Documentation comments exist in DenoFileSystem.res and DenoShell.res
- [ ] No files outside the in-scope list are modified

## STOP conditions

- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).
- A caller is found that passes `shell: true` via `Ports.shellOptions` OTHER than ShellExecutor.res (would require additional cleanup).
- `pnpm build` fails after Step 3 with an error not described above.
- The `shell` field is read by NodeJsShell.res (would require keeping the field and implementing in DenoShell).
- Removing `shell` from `shellOptions` causes a type error in a file not in the in-scope list.

## Maintenance notes

- The `shell?: bool` field was a vestige of Node.js's `child_process.exec` options where `shell: true` means "wrap in sh -c". In this codebase, `execAsync` always wraps in `sh -c` (matching Node semantics) and `execFileAsync` never does (matching Node execFile semantics). The field was never read by either adapter.
- The DenoFileSystem options gap is documented but not fixed — if a caller needs `withFileTypes` or `recursive` on Deno, those must be implemented in the adapter. Currently no caller needs them on the Deno path.
- If the project adds a non-UTF-8 encoding requirement, DenoShell will need to decode `output.bytes` manually instead of using `TextDecoder`.
