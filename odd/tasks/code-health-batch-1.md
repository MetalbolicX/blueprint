# Feature: code-health-batch-1

Source: code-health audit (2026). Three confirmed findings promoted to fixes.
Branch: `fix/code-health-batch-1` (from `main`). Verification: test-first (RED → GREEN) via focused `npx retest ./test/<X>_test.res.mjs` after `pnpm res:build`; full `pnpm res:test` before close.

## Tasks

### T1 — Fix stale `partialCommit` after successful output rollback (H1)
- **Files:** `src/application/pipeline/Phase2.res`, `test/Phase2_test.res`
- **Behavior:** when `Commit.rollbackOutput` succeeds, the returned `phase2Error.partialCommit` must be cleared (`?None`). Applies to both the shell-error path (`{message, partialCommit: committedFiles}` at ~L147 and its catastrophic staging-fail twin) and the commit-error path (`Error(err)` at ~L193 and its staging-fail twin). Paths where `rollbackOutput` fails keep `partialCommit` (genuinely partial tree).
- **Acceptance:** failing test first (RED shows `Some(committedFiles)` today), then GREEN; `Generate.res:97–100` no longer prints "Partially committed files" for fully-restored runs.
- **Status:** done
- **Evidence:** RED: 2 failing assertions (partialCommit present after rollback) → GREEN: Phase2_test.res.mjs 30/30, Phase2Integration_test.res.mjs 9/9. Commit `b0aad2c`. Generate.res unchanged (reads via option; None suppresses report).

### T2 — Propagate malformed pre-hook output as run error (H2)
- **Files:** `src/application/engine/EngineOrchestrator.res`, `test/Engine_test.res`
- **Behavior:** `preResult` must be `Error` when `hookAttributes` is `Error` (malformed hook stdout), matching the documented fail-closed intent. Currently `EngineOrchestrator.res:151–154` maps `Error(_) => None` and the run proceeds — with `io` already closed. Update the stale comment at the `preResult` binding.
- **Acceptance:** failing test first (malformed pre-hook stdout → run fails with parse error), then GREEN; existing pre-hook success tests stay GREEN.
- **Status:** done
- **Evidence:** RED: 1 failing regression test (run returned Ok + file generated) → GREEN: Engine_test.res.mjs 29/29, EngineIntegration_test.res.mjs 5/5. Success fixtures fixed from `echo ok` to `printf '{}'` (they relied on the swallow). Commit `918d6c5`.

### T3 — Router: scope version flag + dedupe usage-error blocks (H3)
- **3a behavior:** `route` treats `-v`/`--version` only when it is `args[0]`; `blueprint generate comp -v` must route to generate, not version. Files: `src/interfaces/cli/Router.res`, `test/Router_test.res` (and `test/Main_test.res` if covered there).
- **3b refactor:** extract one usage-failure helper for the ≥7 repeated `Console.error → Help.printUsage → exit(1)` blocks; no behavior change; existing tests GREEN.
- **Acceptance:** 3a RED→GREEN with a dedicated test; 3b keeps the full Router/Main suites GREEN.
- **Status:** pending
- **Evidence:** —

## Commit plan (work units)

| # | Commit | Unit |
|---|--------|------|
| 1 | `fix(phase2): stop reporting partialCommit after successful output rollback` | T1 + test |
| 2 | `fix(engine): fail run on malformed pre-hook output instead of swallowing` | T2 + test |
| 3 | `fix(router): treat -v/--version only as the leading command` | T3a + test |
| 4 | `refactor(router): extract usage-failure helper` | T3b |

## Close
- Full `pnpm res:test` + `pnpm build` green; record results; report per ODD close.
