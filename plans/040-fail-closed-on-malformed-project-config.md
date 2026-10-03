# Plan 040: Fail closed on a malformed project `.blueprint.yaml`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/interfaces/cli/commands/ConfigContext.res src/interfaces/cli/commands/Generate.res src/interfaces/cli/commands/TemplateCopy.res src/infrastructure/config/ConfigStore.res test/ConfigContext_test.res test/Generate_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (invalid configs stop earlier; valid/absent configs unchanged)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

A project `.blueprint.yaml` that is present but unparsable is silently
discarded (`Error(_) => None`) and generation continues on defaults. A user
who set `dry_run: true` or `shell.enabled: false` (or output/hooks settings)
and then introduced a YAML typo gets a REAL run with REAL writes and shell
execution — with zero diagnostics. The global config path already warns on
parse errors (`ConfigStore.res:94`); the project path is the one carrying
safety-critical settings, and it fails silently.

## Current state

At `100b121`:

- `src/interfaces/cli/commands/ConfigContext.res:23-29` —

```rescript
let configResult = await Config.loadFrom(~fs, ~path, cwd)
let projectConfig = switch configResult {
| Ok(c) => c
| Error(_) => None    // ← parse/load error silently becomes "no config"
}
```

- `Config.loadFrom` returns `result<option<config>, string>`:
  `Ok(None)` = no project config file (allowed), `Ok(Some(c))` = parsed,
  `Error(msg)` = present-but-invalid. Verify this contract at
  `src/infrastructure/config/ConfigStore.res` (`loadFrom`) before editing —
  see STOP conditions.
- Callers of `loadConfigContext`: `src/interfaces/cli/commands/Generate.res:21`
  and `src/interfaces/cli/commands/TemplateCopy.res:9` (grep
  `loadConfigContext` to confirm the full list). Both then call
  `validateMergedConfig` on the merged result.
- Contrast: global config parse errors warn at `ConfigStore.res:94`
  (fail-open-with-warn). This plan makes the PROJECT path fail CLOSED —
  project config is where `dry_run` / `shell.enabled` / hooks live.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Generate_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/interfaces/cli/commands/ConfigContext.res` (+ its type/signature ripple)
- `src/interfaces/cli/commands/Generate.res`
- `src/interfaces/cli/commands/TemplateCopy.res`
- `test/ConfigContext_test.res` (create if absent) and/or the callers' tests

**Out of scope** (do NOT touch):
- `ConfigStore.res` global-config warn-and-continue behavior — global config
  stays fail-open-with-warn (deliberate contrast; note it in your report).
- `Config.loadFrom` internals — do not change its result contract.
- Engine/pipeline behavior — the fix stops the run before the engine.

## Git workflow

- Branch: `fix/040-fail-closed-malformed-project-config`
- Conventional commits, e.g. `fix(config): fail closed when project .blueprint.yaml is invalid`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Pin the contract (READ-ONLY)

Confirm with a quick read of `ConfigStore.loadFrom` that an ABSENT project
config returns `Ok(None)` (not `Error`). If absence also produces `Error`,
STOP — the gate must be reworked around `fileExists` first.

**Verify**: your notes state the absent-file result; no code changed.

### Step 2: Propagate the error through `loadConfigContext`

Change `loadConfigContext` to return
`promise<result<t, string>>`: on `Error(msg)`, return
`Error("Invalid project config <path>: " ++ msg)` where `<path>` is the
resolved `.blueprint.yaml` path (`path.join(cwd, ".blueprint.yaml")` — check
`Config.loadFrom` for the exact filename it reads and reuse it verbatim).

**Verify**: `pnpm res:build` → exit 0 (expect caller compile errors to fix
in Step 3).

### Step 3: Update the callers to exit on error

In `Generate.res` and `TemplateCopy.res` (and any other caller found by
grep): switch on the new result. On `Error(msg)`:
follow the CLI's existing error-exit pattern — look at how `Generate.res`
and `Cli.res` surface engine errors today (they print the message and return
a non-zero exit through the command layer). Match that pattern exactly; do
not invent a new error channel. Generation must stop BEFORE discovery,
hooks, prompts, or any output write.

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → all pass except
possibly tests that asserted silent-continue on bad config (update those —
they enshrined the bug).

### Step 4: Tests (RED first)

Model on existing Generate/config tests (grep `test/` for
`Config.loadFrom` / `.blueprint.yaml` fixtures). With fake fs ports:

1. Project dir contains `.blueprint.yaml` with invalid YAML (e.g. `dry_run: [unclosed`)
   → command returns/exits with an error naming the file; fake fs records
   ZERO writes and zero hook/shell invocations.
2. Project `.blueprint.yaml` with valid `dry_run: true` → dry-run behaves as
   today (regression guard).
3. NO project config file → normal run (regression guard for `Ok(None)`).

Write case 1 first and confirm it FAILS against current behavior (RED),
then confirm GREEN after Steps 2-3.

**Verify**: `npx retest ./test/Generate_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The 3 cases above; model file layout after existing config tests.
- Full-suite gate: any test that relied on silent error-swallowing is
  updated with a comment `// plan 040: fail closed on invalid project config`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new cases
- [ ] `grep -n "Error(_)" src/interfaces/cli/commands/ConfigContext.res` returns no matches (the silent swallow is gone)
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- `Config.loadFrom` returns `Error` for an ABSENT file (contract mismatch —
  gate on `fileExists` first and report the discrepancy).
- The CLI has no existing error-exit pattern you can match (do not invent
  process exits ad hoc — surface the wiring question).
- A caller of `loadConfigContext` NEEDS continue-on-error semantics (e.g. a
  doctor/list command) — surface the decision instead of choosing for it.

## Maintenance notes

- Global config remains warn-and-continue by design; if that asymmetry is
  ever unified, make the global path fail-closed too, not the reverse.
- `SEC-02` in the 2026-10-01 audit pairs with plan 039: a malformed config
  can no longer silently drop `shell.enabled: false`, and the enabled gate
  now actually enforces it.
