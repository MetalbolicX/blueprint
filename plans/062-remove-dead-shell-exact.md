# Plan 062: Delete the dead ShellExact/execAsync execution route

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/domain/exec/ExecPolicy.res src/domain/exec/ExecPolicy.resi src/domain/ports/Ports.res src/domain/ports/Ports.resi src/application/pipeline/ShellExecutor.res src/infrastructure/adapters/NodeJsShell.res src/infrastructure/bindings/NodeJs/ChildProcess.res test/ExecPolicy_test.res test/ShellExecutor_test.res test/NodeJsShell_test.res test/HookSecurity_test.res test/Commands_test.res test/NpmPackInstall_test.res test/res/utils/TestPorts.res`
> NOTE: `Ports.res` legitimately differs between `main` and `b2f2670`
> (LAN-registry added members like `isTTY`, writeFile `mode`) — match by
> symbol names, not line numbers. A semantic change to `execAsync`,
> `ShellExact`, or the shell record is a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (provably dead in production; compiler enumerates every ripple)
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matter

The `ShellExact` decision variant and the `execAsync` port/binding/adapter
chain are dead code left over from the pre-035 world where whole-command
shell execution existed. Nothing constructs `ShellExact` anywhere in the
repository; no production code calls `shell.execAsync` (the only caller
is the adapter implementing it). The variant's own interface comment
admits it: "ShellExact: retained for compatibility; ToolCalls no longer
select this route." Worse, the "dead" arm in `ShellExecutor` doesn't even
use `execAsync` — it calls `execFileAsync` — so the entire chain is
doubly unreachable. Dead execution routes in a security-sensitive shell
executor are pure liability: every future reader must re-verify that this
path can never be reached. The hardening ledger lists these as removal
candidates (`odd/tasks/production-readiness-hardening.md` #6).

## Current state

- `src/domain/exec/ExecPolicy.res:24-27` — the variant:
  ```rescript
  type decision =
    | ExecFile(string, array<string>)
    | ShellExact(string)
    | Reject(string)
  ```
  `decide` (`ExecPolicy.res:36-43`) returns only `Reject` or `ExecFile`.
  Stale doc comment at `:3` ("Decides between ExecFile(command, args),
  ShellExact(command), or Reject(reason).").
- `src/domain/exec/ExecPolicy.resi:14` — `*  - ShellExact: retained for
  compatibility; ToolCalls no longer select this route.` (decl at `:19`).
- `src/application/pipeline/ShellExecutor.res:133-141` — the unreachable arm:
  ```rescript
  | ShellExact(command) => execToolAsync(
      ~run=(~options) => shell.execFileAsync(command, ~options),
  ```
  plus the stale helper comment at `:16` "(execFileAsync or execAsync)".
- `src/domain/ports/Ports.res:116` (and `Ports.resi:64`) — port member:
  `execAsync: (string, ~options: shellOptions=?) => promise<execResult>,`
- `src/infrastructure/adapters/NodeJsShell.res:8,13` — adapter record
  field and its only implementation
  (`(execAsync(cmd, ~options=?opts) :> promise<Ports.execResult>)`).
- `src/infrastructure/bindings/NodeJs/ChildProcess.res:77-81` — the raw
  `exec` binding (`execAsync`, "callback API internally").
- **All `ShellExact(` occurrences** (verified by grep at planned-at
  commit): `ExecPolicy.res:3,25`, `ExecPolicy.resi:19`,
  `ShellExecutor.res:133`, `test/ExecPolicy_test.res:25,54` (negative
  assertions only). **No construction site exists.**
- **All `execAsync(` callers**: adapter implementation only in `src/`
  (`NodeJsShell.res:13`); in tests: `test/NodeJsShell_test.res:8` (real
  exec), `test/Commands_test.res:53-55` (delegate mock), test record
  literals and zero-count assertions at
  `test/ShellExecutor_test.res:482,517,540`,
  `test/HookSecurity_test.res:524`, `test/NpmPackInstall_test.res:59-62`,
  and `test/res/utils/TestPorts.res` (stub record field).

Conventions: removal-only change; the ReScript compiler enumerates every
record-literal ripple (missing/extra fields are compile errors) — use
that as the worklist. House rule from `odd/tasks/code-health-batch-2.md`:
grep callers first; remove ONLY zero-caller items (both targets here are
proven zero-production-caller above).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0, no new warnings |
| Focused | `npx retest ./test/ExecPolicy_test.res.mjs` (also ShellExecutor, NodeJsShell, HookSecurity, Commands, NpmPackInstall) | all pass |
| Full suite | `pnpm res:test` | all pass, exit 0 |
| Dead-code gone | `grep -rn "execAsync\|ShellExact" src/ test/ --include="*.res" --include="*.resi"` | no matches |

## Scope

**In scope**:
- `src/domain/exec/ExecPolicy.res` / `.resi`
- `src/domain/ports/Ports.res` / `.resi`
- `src/application/pipeline/ShellExecutor.res`
- `src/infrastructure/adapters/NodeJsShell.res`
- `src/infrastructure/bindings/NodeJs/ChildProcess.res`
- `test/ExecPolicy_test.res`, `test/ShellExecutor_test.res`,
  `test/NodeJsShell_test.res`, `test/HookSecurity_test.res`,
  `test/Commands_test.res`, `test/NpmPackInstall_test.res`,
  `test/res/utils/TestPorts.res` / `.resi`

**Out of scope**:
- `ExecFile` / `execFileAsync` (the live route); `Reject`;
  allowlist matching (plan 035 behavior); any hook timeout semantics.

## Git workflow

- Branch: `chore/062-remove-dead-shell-exact`
- Commit style: `chore(exec): remove dead ShellExact route and execAsync port chain`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: Remove the decision variant

- Delete `ShellExact(string)` from `ExecPolicy.res:25` and
  `ExecPolicy.resi:19`; fix the doc comments (`ExecPolicy.res:3`,
  `ExecPolicy.resi:14`) to describe only `ExecFile`/`Reject`.
- Delete the match arm `ShellExecutor.res:133-141`; fix the `:16`
  comment to "(execFileAsync)".
- Update `test/ExecPolicy_test.res:25,54`: the negative assertions that
  `decide` never returns `ShellExact` can no longer compile against a
  removed variant — replace with (or keep existing) assertions that
  `decide` returns only `ExecFile`/`Reject` shapes for the same inputs.

**Verify**: `pnpm res:build` → exit 0 (compiler lists any remaining ripples — fix them).

### Step 2: Remove the `execAsync` chain

- Delete the port member (`Ports.res:116`, `Ports.resi:64`), the adapter
  field + implementation (`NodeJsShell.res:8,13`), and the binding
  (`ChildProcess.res:77-81`).
- The compiler now flags every shell-record literal missing/extra the
  field — update each: drop the field from `TestPorts` stubs and test
  literals; delete the zero-count assertions
  (`ShellExecutor_test.res:482,517,540`), the rejects-if-called guard
  (`HookSecurity_test.res:524`), the delegate mock
  (`Commands_test.res:53-55`), the real-exec adapter test
  (`NodeJsShell_test.res:8`), and the constructor use
  (`NpmPackInstall_test.res:59-62`). Preserve each test's remaining
  intent — do not delete whole tests unless their only subject was
  `execAsync`.

**Verify**: `pnpm res:build` → exit 0, zero warnings.

### Step 3: Gates

**Verify**: `grep -rn "execAsync\|ShellExact" src/ test/ --include="*.res" --include="*.resi"` → no matches (`.res.mjs` artifacts regenerate on build; do not hand-edit them). `npx retest ./test/ExecPolicy_test.res.mjs ./test/ShellExecutor_test.res.mjs` → pass; `pnpm res:test` → all pass, exit 0.

## Test plan

- Removal-only: no new tests. Existing suites must stay green with the
  field/variant gone; tests whose only subject was the dead route are
  deleted with justification in the commit body.

## Done criteria

- [ ] `pnpm res:build` exit 0, zero new warnings
- [ ] `pnpm res:test` exit 0
- [ ] grep gate returns no matches
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The compiler reveals a REAL production construction/call site of
  `ShellExact` or `shell.execAsync` (contradicts the audit — report it;
  do not delete a live route).
- Removing the `Ports.shell` field forces semantic changes beyond
  record-literal updates.

## Maintenance notes

- This closes hardening-ledger item #6's removal half (the stale doc
  comment half is fixed in Step 1).
- Reviewer focus: the two ExecPolicy test rewrites must not weaken the
  plan-035 allowlist assertions.
