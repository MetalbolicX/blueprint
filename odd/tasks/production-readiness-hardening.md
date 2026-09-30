# Feature: production-readiness-hardening

## Objective

Close the blockers and high-severity findings from the 2025 production-readiness audit so Blueprint can ship.

## Problem / Why

A four-agent audit (pipeline/domain, infrastructure/security, build/test verification, CLI/test quality) found the codebase not production ready: a data-destroying conflict-prompt trap, an SSRF guard bypassable via redirects, no EOF/non-TTY handling, signal handling that destroys recovery backups mid-commit, a hook containment check that validates a different path than it executes, and CLI/CI/packaging gaps (no `--version`, dead `readyz`, CI bundling after the tests that need the bundle, dist-less `npm pack` tarball, 4 deprecation warnings, 1 failing test).

## Scope

Six work units (WU1–WU6), each one delegated writer → parent verification → work-unit commit. Baseline audit memory: Engram observation id 632 (topic audit-production-readiness).

## Constraints

- Strict TDD (user mandate): observed RED before implementation, GREEN, then REFACTOR. Evidence recorded per task.
- Runner: `retest` — focused `npx retest ./test/<file>.res.mjs`, full suite `pnpm res:test`.
- Generated artifacts in English. Conventional Commits. Writers never commit; parent commits.
- Known baseline failure: test 643 "template command flow installs, lists, and removes a template" (pre-existing, fixed in WU6) — must not mask new failures elsewhere.
- Staging-root unification (WU4) must use one derivation (`os.tmpdir()`), not env sniffing.

## Delivery strategy

**stacked-to-main** (user choice): each work unit becomes a small PR stacked on the previous, landing on main one by one. Push/PR/merge confirmed with the user at each boundary.

- Forecast: ~750–900 authored changed lines (over ~400 budget → strategy applied up front).
- First reviewed boundary: branch point `991fdbf` (main).

## TDD / checks

- Mode: **strict TDD**. Source: explicit user choice. Runner: retest.
- RDD: on (global). After each work-unit commit: `gentle_review` assess with `{"baseRef":"<last reviewed boundary>","committedOnly":true}`; passive/low → boundary advances; high → native review at that base; medium → defer to slice close.

## Checklist

### T1 — Conflict abort trap (WU1) — pending
- `parseChoice`: `"a" | "abort"` → `Abort`; `"all"` → `YesAll`; remove unadvertised `"q"` alias; keep y/yes, n/no, s/select.
- `ConflictRunner` bulk prompt spells out the exact contract (advertises `[a]bort`; documents typing `all` = overwrite everything).
- Select mode: unrecognized input re-prompts with feedback; `abort` aborts mid-select.
- Tests: fix enshrined `a → YesAll` assertion; add prompt-contract test covering every advertised key.
- Acceptance: focused tests green; full suite no new failures. Commit: `fix(conflicts): make 'a' abort instead of overwrite-all`.

### T2 — SSRF hardening (WU2) — pending
- `Fetcher.httpGetOnce`: `redirect: "manual"` + explicit redirect loop that re-runs `SsrfGuard.isUrlAllowed` on every `Location` hop (cap hops ≤5, reject non-http(s)).
- Response body size cap (e.g. 10 MiB) — fail closed.
- `SsrfGuard`: fix `parseIpv6` end-padding bug; classify `::ffff:`/`0:0:...:ffff:` mapped forms as IPv4-equivalent; add 100.64/10, 224/4, 240/4, 255.255.255.255, fec0::/10.
- `ShellExecutor`: fetch staging filename uses collision-resistant hash (not 31-bit imul).
- DNS-rebinding connect-time pinning: document as residual risk in code + here (undici dispatcher follow-up).
- Acceptance: SsrfGuard/Fetcher tests cover redirect-to-metadata rejection, mapped-IPv6 rejection, new ranges; focused green; full suite no new failures. Commit: `fix(security): close SSRF redirect bypass and IP classification gaps`.

### T3 — EOF/non-TTY + process lifecycle (WU3) — pending
- Readline binding exposes close/EOF events; `NodeJsInteractiveIO.question` rejects cleanly on EOF.
- Non-TTY stdin + required prompt → actionable error + exit 1 (no hang, no silent exit).
- Readline created lazily; commands that never prompt never open it; success paths close IO and exit 0 (`init`, `init --global`, `generator list/add-prompt/add-file`).
- Acceptance: EOF/non-TTY tests for conflict prompt + one command; focused green; full suite no new failures. Commit: `fix(cli): handle EOF/non-TTY stdin and close interactive loops`.

### T4 — Transactional integrity (WU4) — pending
- Signal handler must not delete staging mid-commit: during Phase2 commit, SIGINT/SIGTERM triggers output rollback (restoring backups) then cleanup; before commit, staging-only cleanup as today.
- Single tmpRoot derivation via `os.tmpdir()` shared by Phase2/EngineOrchestrator/EngineLifecycle/Commit guard.
- Failed staging cleanup no longer silent on success path (surface warning).
- Post-hook failure after commit reports partial-commit state explicitly (Generate error path).
- Orphan sweep: skip dirs whose mtime advanced within threshold; never delete a staging dir younger than the sweep age.
- Acceptance: signal-mid-commit test asserts backups restore; tmpRoot guard test; focused green; full suite no new failures. Commit: `fix(pipeline): protect backups from signals, unify staging root`.

### T5 — Hook execution boundary (WU5) — pending
- `Hooks`: resolve once, validate the resolved path, execute that same absolute path.
- Allowlist authoritative for all routes (arg-less, with-args, path commands); configured-but-empty allowlist denies; `shell.enabled=false` gates hooks too.
- Hook timeout upper bound (cap 600s); tokenized hooks run with declared cwd.
- Remove unused full-env `execShellCommand` from Ports.shell (or restrict env via EnvFilter).
- Acceptance: HookSecurity tests cover resolved-path execution + enabled=false denial; focused green; full suite no new failures. Commit: `fix(hooks): enforce execution boundary and allowlist on all routes`.

### T6 — CLI/CI/packaging (WU6) — pending
- `--version` flag (reads package.json version); `help <unknown>` → exit 1 + stderr.
- `readyz`: wire `ProbeState.setReady` after engine/config init on generate.
- CI: bundle before the tests that need `dist/main.mjs`; add `prepack` (full build) so `npm pack` ships a working tarball.
- Fix 4 `Js.Date` deprecation warnings in `TemplateRegistry.res`; diagnose + fix failing test 643; refresh stale "No CI detected" note in AGENTS.md.
- Acceptance: version/help tests; test 643 green; full suite 696/696; clean build zero warnings; `npm pack` tarball contains dist. Commit: `chore(cli): add version flag, fix readyz, CI order, prepack and warnings`.

### T7 — Close-out — pending
- Full suite + clean build final run; AGENTS.md/docs updated; Engram mirror synced; stacked PRs prepared per user confirmation.

## Progress log

- 2025 audit completed (read-only); verdict: not production ready. Memory id 632.
- Branch `fix/production-readiness-hardening` created off `main` @ `991fdbf`.
- Delivery strategy resolved: stacked-to-main (user). TDD: strict (user mandate).

## Per-task evidence record

| Task | Commit | Assess tier | Outcome |
|------|--------|-------------|---------|
| T1 | — | — | — |
| T2 | — | — | — |
| T3 | — | — | — |
| T4 | — | — | — |
| T5 | — | — | — |
| T6 | — | — | — |

## Next step

Delegate T1 to gentle-ai-worker (strict TDD), verify, commit, assess.
