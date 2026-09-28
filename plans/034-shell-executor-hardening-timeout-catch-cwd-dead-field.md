# Plan 034: ShellExecutor hardening — inline timeout, terminal catch, script cwd, dead field

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0267337..HEAD -- src/infrastructure/bindings/NodeJs/ChildProcess.res src/application/pipeline/ShellExecutor.res test/ShellExecutor_test.res src/application/pipeline/Phase2.res src/application/pipeline/Phase2.resi src/application/engine/EngineResult.res src/application/engine/EngineResult.resi src/application/engine/EngineOrchestrator.res src/interfaces/cli/commands/Generate.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M (four small fixes in one file cluster)
- **Risk**: LOW–MED (terminal catch must not mask programming errors)
- **Depends on**: none (but execute after plans 033 to avoid test-file conflicts
  in `Phase2_test.res` — this plan touches `Phase2.res` only for the field removal)
- **Category**: bug
- **Planned at**: commit `0267337`, 2026-09-27

## Why this matters

Four defects in the shell-execution path, each small, together undermining
reliability: (1) an inline `sh:` command that never exits hangs the CLI
forever — the timeout code path exists but is unreachable dead code; (2) a
single rejected promise inside `executeShellCommands` escapes as an unhandled
rejection and bypasses EVERY rollback branch, leaving staging, committed
output, and fetch temp files behind; (3) script-file paths resolve against the
process cwd instead of the project cwd, so running the CLI from another
directory breaks relative script paths; (4) the `shellErrors` field is
hard-wired to `[]` — dead API plumbed all the way to CLI display.

## Current state

ReScript 12 CLI. Shell execution flows through `ShellExecutor.res`
(application) → `ChildProcess.res` binding (infrastructure). Relevant facts at
`0267337`:

- `src/infrastructure/bindings/NodeJs/ChildProcess.res:15-20` — `execOptions`
  type ALREADY supports a `timeout` field.
- `src/infrastructure/bindings/NodeJs/ChildProcess.res:116-122` —
  `execShellCommand` builds options with only `cwd`/`encoding`; no `timeout`.
- `src/infrastructure/bindings/NodeJs/ChildProcess.res:123-124` — checks
  `result.killed` → returns "Command timed out" — dead code today (options
  never carry a timeout).
- `src/application/pipeline/ShellExecutor.res:30` and `:203` — ToolCall and
  ScriptFile paths DO pass `ExecPolicy.defaultTimeout` (defined at
  `src/domain/exec/ExecPolicy.res:13`, comment: "must stop every tool/script
  run that exceeds 30 seconds").
- `src/application/pipeline/ShellExecutor.res:162` — inline command path calls
  `execShellCommand` with NO timeout.
- `src/application/pipeline/ShellExecutor.res:256-308` —
  `executeShellCommands`: the reduce chain and final `.then` have NO `.catch`;
  `cleanupFetchTmpFiles` (`:301-308`) runs only in the fulfilled handler;
  `:60` — `Fetcher.fetch(url)->Promise.then(...)` has no outer catch.
- `src/application/pipeline/ShellExecutor.res:190` —
  `let resolvedPath = path.resolve(cmdPath, "")` — anchors to process cwd.
  Contrast `:157` (correct pattern): `path.resolve(cwd, baseCmd)`.
- `src/application/pipeline/ShellExecutor.res:304` — success always returns
  `Ok((count.contents, []))` — hard-coded empty `shellErrors`.
- `shellErrors` consumer chain (remove in Step 4):
  `src/application/pipeline/Phase2.res:12` (field in `phase2Result`),
  `Phase2.resi:5`, `src/application/engine/EngineResult.res:9` +
  `EngineResult.resi:8`, `src/application/engine/EngineOrchestrator.res:226`,
  `src/interfaces/cli/commands/Generate.res:99` (display switch).

### Repo conventions to honor

- Result-style error handling (`result<_, string>`), `Errors.extractErrorMessage`
  helper at `src/infrastructure/bindings/Errors.res:5` (already used at
  `ShellExecutor.res:45,80,220`) — reuse it in the terminal catch.
- Optional record fields use `?` style; `Some(x) ? x : None` idiom appears at
  `Phase2.res:77`.
- No comments in source unless asked.
- Test style: `test/ShellExecutor_test.res` — `open TestHelpers`,
  `testAsync`, injected `~shell` port mocks (see tests at `:327`, `:361`,
  `:463` for the mock shape).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile (= typecheck) | `pnpm res:build` | exit 0 |
| Run all tests | `pnpm res:test` | all pass |
| Run ShellExecutor tests only | `npx retest ./test/ShellExecutor_test.res.mjs` | all pass |

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/bindings/NodeJs/ChildProcess.res` — timeout option.
- `src/application/pipeline/ShellExecutor.res` — timeout passthrough, terminal
  catch, cwd fix, dead-array removal.
- `src/application/pipeline/Phase2.res` + `Phase2.resi`,
  `src/application/engine/EngineResult.res` + `EngineResult.resi`,
  `src/application/engine/EngineOrchestrator.res`,
  `src/interfaces/cli/commands/Generate.res` — `shellErrors` field removal only.
- `test/ShellExecutor_test.res` — new tests.

**Out of scope** (do NOT touch):
- `ExecPolicy.res` (the 30s constant is already right; plan 036 handles its
  contract comment).
- Allowlist matching semantics (plan 035).
- `Fetcher`/`PathSecurity` internals — only their failure SURFACING changes here.
- Hooks (plan 036).

## Git workflow

- Branch: `fix/shell-executor-hardening`
- Conventional commits, one per step. Repo style: `fix(...)`, `test(...)`, `refactor(...)`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Thread timeout through `execShellCommand`

Commit message: `fix(shell): apply the 30s policy timeout to inline sh commands`

1. `ChildProcess.res:116-122` — add an optional `~timeout: option<int>=?`
   labeled argument to `execShellCommand`; when `Some(t)`, include
   `timeout: t` in the options object passed to `exec`. The existing
   `result.killed` → "Command timed out" mapping at `:123-124` becomes live.
2. `ShellExecutor.res:162` — pass `~timeout=Some(ExecPolicy.defaultTimeout)`
   (mirroring `:30` and `:203`).

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Terminal rejection handler + always-run fetch cleanup

Commit message: `fix(shell): catch rejections in executeShellCommands and always clean fetch tmp files`

In `ShellExecutor.res:256-308` (`executeShellCommands`):

1. Append a terminal catch to the whole chain:
   `.catch(e => Error(Errors.extractErrorMessage(e)))` typed to the function's
   `result` return. Rejections must surface as `Error`, never throw through
   `Phase2.run`.
2. Move `cleanupFetchTmpFiles` so it runs on BOTH fulfilled and rejected
   outcomes (split the final `.then` into fulfilled/rejected handlers, or run
   cleanup first then re-propagate). Cleanup failures stay best-effort (they
   already resolve to `()` at `:11`).

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/ShellExecutor_test.res.mjs` → existing tests pass.

### Step 3: Resolve script paths against the project cwd

Commit message: `fix(shell): resolve script paths against project cwd, not process cwd`

`ShellExecutor.res:190` — change `path.resolve(cmdPath, "")` to
`path.resolve(cwd, cmdPath)` (same pattern as `:157`). The subsequent
`isWithinTree(resolvedPath, cwd, ...)` validation at `:191` is unchanged.

**Verify**: `pnpm res:build` → exit 0.

### Step 4: Remove the dead `shellErrors` field

Commit message: `refactor(shell): remove dead shellErrors field`

`executeShellCommands` short-circuits on the first error by design, so
`shellErrors` can never be non-empty (`ShellExecutor.res:259`, `:304`). Remove
the field through its whole chain:

1. `ShellExecutor.res` — return `result<int, string>` instead of
   `result<(int, array<string>), string>`; update `Phase2.res:74-84`
   accordingly (drop the `shellErrs` computation at `:77`).
2. Delete the field from `phase2Result` (`Phase2.res:12`, `Phase2.resi:5`),
   `EngineResult.res:9` + `.resi:8`, the pass-through at
   `EngineOrchestrator.res:226`, and the display switch at `Generate.res:99`.

**Verify**: `pnpm res:build` → exit 0 (compiler finds every remaining consumer);
`pnpm res:test` → all pass.

### Step 5: Tests

Commit message: `test(shell): timeout passthrough, rejection containment, cwd resolution`

Add to `test/ShellExecutor_test.res` (existing mock style):

1. Timeout contract: invoke the inline path with a mocked `~shell` port whose
   `exec` records the options it receives; assert a `timeout` field is present
   and equals 30000. (Port mocks cannot elapse real time — asserting the
   option IS the contract.)
2. Rejection containment: mock `Fetcher.fetch` (or the shell port) to return a
   rejecting promise; assert `executeShellCommands` resolves to `Error(...)`
   — not an unhandled rejection — and that fetch tmp cleanup ran.
3. Cwd resolution: script-file command with a relative path; assert the
   resolved path passed to the port mock starts with the passed `~cwd`, not
   `process.cwd()`.

**Verify**: `npx retest ./test/ShellExecutor_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The three cases above; model mocks on existing tests at
  `test/ShellExecutor_test.res:327,361,463`.
- Full-suite gate confirms the `shellErrors` removal broke nothing
  (`EngineResult`/`Generate` tests may reference the field — update those
  EXPECTATIONS, do not re-add the field).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 with the three new tests passing
- [ ] `grep -rn "shellErrors" src/ test/` returns no matches
- [ ] `grep -n "resolve(cmdPath" src/application/pipeline/ShellExecutor.res` returns no match
- [ ] `grep -n "timeout" src/infrastructure/bindings/NodeJs/ChildProcess.res` shows the option wired in `execShellCommand`
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Drift vs the excerpts above (since `0267337`).
- The `shellErrors` removal surfaces a consumer that semantically NEEDS partial
  shell-error reporting (report it; do not re-plumb speculative warnings).
- Existing `EngineResult`/`Generate`/`Phase2` tests fail in ways not covered by
  the "update expectations" guidance.
- The mocked-shell port cannot capture received options (no spy seam) — report
  rather than adding test-only code to production modules.

## Maintenance notes

- Plan 035 (allowlist) and 036 (hooks) also modify `ShellExecutor.res` and
  `ExecPolicy` — land this plan before those to avoid conflicts.
- A real-clock timeout test (spawn `sleep 999`) would be nice but the suite is
  port-mocked by design; the option-assertion is the accepted contract.
