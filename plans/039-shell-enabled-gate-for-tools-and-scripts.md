# Plan 039: Enforce `shell.enabled` for tool calls and script files

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/application/pipeline/ShellExecutor.res src/application/pipeline/ShellExecutor.resi src/application/pipeline/ShellQueue.res test/ShellExecutor_test.res test/ShellQueue_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (one localized policy check per route; behavior change is the point)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `100b121`, 2026-10-01
- **Decision (2026-10-02, maintainer ruling)**: the STOP-condition question
  "does `enabled` default to true?" is resolved: **keep the parser default
  `false`** (`ConfigJsonParser.res:197`). Strict fail-closed: a `shell:`
  section without an explicit `enabled: true` gets NO tool/script execution
  after this plan lands. Accepted breaking change; the
  `Error("Shell execution disabled")` message is the migration guide.
  Do NOT change the parser default.

## Why this matters

`shell.enabled: false` in `.blueprint.yaml` is documented as the switch that
governs template-driven command execution, but only one route honors it. Tool
calls (structured-args `sh:` directives) and script files execute regardless,
so an operator who disables shell execution as a safety switch still gets
template-initiated process execution. The design doc
(`docs/superpowers/specs/2026-05-21-js-templates-design.md:149`) states
scripts require `enabled: true` and are otherwise skipped — the code and the
spec disagree, and the code is the unsafe side of the disagreement.

## Current state

At `100b121`:

- `src/application/pipeline/ShellExecutor.res:98-137` — `executeToolCall`
  takes `~shellConfig: option<Config.shellConfig>` (used only to build the
  tools allowlist) and never checks `cfg.enabled`. Executes via
  `ExecPolicy.decide` → `execToolAsync`.
- `src/application/pipeline/ShellExecutor.res:205-243` — `executeScriptFile`
  has NO `~shellConfig` parameter at all. It only validates path containment
  and file existence, then runs `shell.execFileAsync(resolvedPath, ...)`.
- `src/application/pipeline/ShellExecutor.res:147-151` — `executeInlineCommand`
  is the only route that gates: `shellEnabled = switch shellConfig { | Some(cfg) => cfg.enabled | None => false }`, returning
  `Error("Shell execution disabled")` when false. Note: this route is
  currently unreachable (no `InlineCommand` producer) — do not remove it in
  this plan; just mirror its gate.
- `src/application/pipeline/ShellExecutor.res:254+` — `executeShellCommands`
  is the dispatcher (exported via `.resi`); it has `~shellConfig` and routes
  each queued command variant to the handlers above. Fetch (`executeFetch`,
  `:60-90`) is a network read and is NOT in scope.
- `src/infrastructure/hooks/Hooks.res:193-199` — hooks already enforce the
  same `enabled` gate (read it to confirm the pattern).
- `src/application/pipeline/ShellQueue.res:50-79` — queue construction
  hard-errors when tools/scripts are referenced but unconfigured (fail-closed
  precedent).
- Gate semantics to mirror exactly (from `executeInlineCommand`):
  `Some(cfg) => cfg.enabled | None => false`.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/ShellExecutor_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them; `git status --short` will not list them.

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/ShellExecutor.res`
- `src/application/pipeline/ShellExecutor.resi` (only if a signature changes)
- `test/ShellExecutor_test.res`

**Out of scope** (do NOT touch):
- `executeFetch` and any fetch/SSRF logic — network reads, separate policy.
- `src/domain/exec/ExecPolicy.res` — structured-args allowlist semantics are
  by-design (documented at `ExecPolicy.res:17-31`); do not "fix" them.
- `Hooks.res` — already gated.
- Historical design docs under `docs/superpowers/specs/` — they are dated
  records; do not rewrite history. Record the reconciliation in
  `plans/README.md` and README's shell section only if it mentions `enabled`.

## Git workflow

- Branch: `fix/039-shell-enabled-gate`
- Conventional commits, e.g. `fix(exec): enforce shell.enabled on tool and script routes`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Gate `executeToolCall`

At the top of `executeToolCall` (before `ExecPolicy.decide`), add:

```rescript
let shellEnabled = switch shellConfig {
| Some(cfg) => cfg.enabled
| None => false
}
if !shellEnabled {
  Promise.resolve(Error("Shell execution disabled"))
} else {
  // ...existing body unchanged
}
```

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Thread `~shellConfig` into `executeScriptFile` and gate it

1. Add `~shellConfig: option<Config.shellConfig>` to `executeScriptFile`'s
   parameters (first param, matching `executeToolCall`'s style).
2. Add the identical gate at the top, before `path.resolve`.
3. Update the call site in `executeShellCommands` to pass `~shellConfig`
   (it already receives it). Grep for other `executeScriptFile` callers:
   `grep -rn "executeScriptFile" src/ test/` — update every caller.

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → only NEW failures
allowed are tests asserting script/tool execution WITHOUT a shell config
(see Step 3).

### Step 3: Tests (RED first, then GREEN)

In `test/ShellExecutor_test.res` (it has ~900 lines with an injected fake
shell port that records `execFileAsync` calls — reuse that harness):

1. ToolCall with `shellConfig = Some({enabled: false, ...})` → result is
   `Error("Shell execution disabled")` AND the fake shell port recorded zero
   executions.
2. ScriptFile with the same disabled config → `Error`, zero executions.
3. ScriptFile/ToolCall with `enabled: true` (and allowlisted command) →
   executes exactly as today (regression guard).
4. `shellConfig = None` → both routes refuse (matches inline semantics).

Write the disabled-route tests FIRST and confirm they fail against the
unpatched behavior (RED), then apply Steps 1-2 and confirm GREEN.

**Verify**: `npx retest ./test/ShellExecutor_test.res.mjs` → all pass,
including the 4 new cases; `pnpm res:test` → all pass.

## Test plan

- The 4 cases above in `test/ShellExecutor_test.res`.
- Full-suite gate confirms no other route depended on ungated execution.
- If existing tests elsewhere (e.g. `test/Phase2_test.res`,
  `test/ShellQueue_test.res`) asserted tool/script execution without a
  shell config, update them to configure `enabled: true` explicitly and add
  a comment `// shell.enabled gate (plan 039)`. That is a deliberate,
  documented behavior change — list every such test in your report.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new gate tests
- [ ] `grep -n "Shell execution disabled" src/application/pipeline/ShellExecutor.res` shows the gate in BOTH `executeToolCall` and `executeScriptFile`
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- ~~`Config.shellConfig`'s `enabled` field does NOT default to `true`...~~
  RESOLVED 2026-10-02 by maintainer ruling: default stays `false`; proceed
  (see Status). Note: `README.md` does not document `enabled` at all — the
  doc gap is recorded in `plans/README.md`, not fixed here.
- More than ~10 existing tests break for reasons other than "expected
  execution without shell config" — the gate may be biting a different
  contract than this plan assumed.
- `executeScriptFile` has callers outside `ShellExecutor.res` that cannot
  supply `~shellConfig`.

## Maintenance notes

- Behavior change: template `sh:` tool calls and script files now require
  `shell.enabled: true` (and an existing tools config) to run. The
  historical spec `docs/superpowers/specs/2026-05-21-js-templates-design.md:149`
  said "silently skipped"; the implemented behavior is a hard `Error`
  (fail-closed, consistent with `ShellQueue.res:50-79`). Do not edit the
  dated spec; note the reconciliation in `plans/README.md`.
- If a per-route policy matrix is ever extracted (see plan 050's direction),
  this gate is one of the routes to centralize.
- Fetch routes are intentionally ungated here; if fetch policy is added
  later, keep it a separate decision.
