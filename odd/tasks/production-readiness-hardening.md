# Feature: production-readiness-hardening

## Objective

Close the blockers and high-severity findings from the 2025 production-readiness audit so Blueprint can ship.

## Problem / Why

A four-agent audit (pipeline/domain, infrastructure/security, build/test verification, CLI/test quality) found the codebase not production ready: a data-destroying conflict-prompt trap, an SSRF guard bypassable via redirects, no EOF/non-TTY handling, signal handling that destroys recovery backups mid-commit, a hook containment check that validates a different path than it executes, and CLI/CI/packaging gaps (no `--version`, dead `readyz`, CI bundling after the tests that need the bundle, dist-less `npm pack` tarball, 4 deprecation warnings, 1 failing test).

## Scope

Six implementation work units (WU1–WU6), two verifier-driven fix-forward commits, and a tracked progress document. Baseline audit memory: Engram observation id 6327 (topic audit-production-readiness).

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

### T1 — Conflict abort trap (WU1) — done (commit 84b42b7)
- `parseChoice`: `"a" | "abort"` → `Abort`; `"all"` → `YesAll`; remove unadvertised `"q"` alias; keep y/yes, n/no, s/select.
- `ConflictRunner` bulk prompt spells out the exact contract (advertises `[a]bort`; documents typing `all` = overwrite everything).
- Select mode: unrecognized input re-prompts with feedback; `abort` aborts mid-select.
- Tests: fix enshrined `a → YesAll` assertion; add prompt-contract test covering every advertised key.
- Acceptance: focused tests green; full suite no new failures. Commit: `fix(conflicts): make 'a' abort instead of overwrite-all`.

### T2 — SSRF hardening (WU2) — done (commit 86198c2)
- `Fetcher.httpGetOnce`: `redirect: "manual"` + explicit redirect loop that re-runs `SsrfGuard.isUrlAllowed` on every `Location` hop (cap hops ≤5, reject non-http(s)).
- Response body size cap (e.g. 10 MiB) — fail closed.
- `SsrfGuard`: fix `parseIpv6` end-padding bug; classify `::ffff:`/`0:0:...:ffff:` mapped forms as IPv4-equivalent; add 100.64/10, 224/4, 240/4, 255.255.255.255, fec0::/10.
- `ShellExecutor`: fetch staging filename uses collision-resistant hash (not 31-bit imul).
- DNS-rebinding connect-time pinning: document as residual risk in code + here (undici dispatcher follow-up).
- Acceptance: SsrfGuard/Fetcher tests cover redirect-to-metadata rejection, mapped-IPv6 rejection, new ranges; focused green; full suite no new failures. Commit: `fix(security): close SSRF redirect bypass and IP classification gaps`.

### T3 — EOF/non-TTY + process lifecycle (WU3) — done (commit 8a0e861)
- Readline binding exposes close/EOF events; `NodeJsInteractiveIO.question` rejects cleanly on EOF.
- Non-TTY stdin + required prompt → actionable error + exit 1 (no hang, no silent exit).
- Readline created lazily; commands that never prompt never open it; success paths close IO and exit 0 (`init`, `init --global`, `generator list/add-prompt/add-file`).
- Acceptance: EOF/non-TTY tests for conflict prompt + one command; focused green; full suite no new failures. Commit: `fix(cli): handle EOF/non-TTY stdin and close interactive loops`.

### T4 — Transactional integrity (WU4) — done (commit f441c4f)
- Signal handler must not delete staging mid-commit: during Phase2 commit, SIGINT/SIGTERM triggers output rollback (restoring backups) then cleanup; before commit, staging-only cleanup as today.
- Single tmpRoot derivation via `os.tmpdir()` shared by Phase2/EngineOrchestrator/EngineLifecycle/Commit guard.
- Failed staging cleanup no longer silent on success path (surface warning).
- Post-hook failure after commit reports partial-commit state explicitly (Generate error path).
- Orphan sweep: skip dirs whose mtime advanced within threshold; never delete a staging dir younger than the sweep age.
- Acceptance: signal-mid-commit test asserts backups restore; tmpRoot guard test; focused green; full suite no new failures. Commit: `fix(pipeline): protect backups from signals, unify staging root`.

### T5 — Hook execution boundary (WU5) — done (commit 9d7ef5b)
- `Hooks`: resolve once, validate the resolved path, execute that same absolute path.
- Allowlist authoritative for all routes (arg-less, with-args, path commands); configured-but-empty allowlist denies; `shell.enabled=false` gates hooks too.
- Hook timeout upper bound (cap 600s); tokenized hooks run with declared cwd.
- Remove unused full-env `execShellCommand` from Ports.shell (or restrict env via EnvFilter).
- Acceptance: HookSecurity tests cover resolved-path execution + enabled=false denial; focused green; full suite no new failures. Commit: `fix(hooks): enforce execution boundary and allowlist on all routes`.

### T6 — CLI/CI/packaging (WU6) — done (commit 8f85e34; baseline-test fix via parent-approved test/TemplateIntegration_test.res)
- `--version` flag (reads package.json version); `help <unknown>` → exit 1 + stderr.
- `readyz`: wire `ProbeState.setReady` after engine/config init on generate.
- CI: bundle before the tests that need `dist/main.mjs`; add `prepack` (full build) so `npm pack` ships a working tarball.
- Fix 4 `Js.Date` deprecation warnings in `TemplateRegistry.res`; diagnose + fix failing test 643; refresh stale "No CI detected" note in AGENTS.md.
- Acceptance: version/help tests; formerly failing template-copy integration test green; full suite green; clean build zero warnings; `npm pack` tarball contains dist. Commit: `chore(cli): add version flag, fix readyz, CI order, prepack and warnings`.

### T7 — Close-out — done (T6 verifier finding fixed in 6265dab; local slice branches cut; remote push blocked by SSH credentials)
- Full suite + clean build final run; AGENTS.md/docs updated; Engram mirror synced; stacked PRs prepared per user confirmation.

## Progress log

- 2025 audit completed (read-only); verdict: not production ready. Memory id 632.
- Branch `fix/production-readiness-hardening` created off `main` @ `991fdbf`.
- Delivery strategy resolved: stacked-to-main (user). TDD: strict (user mandate).
- T1 committed 84b42b7 (+136/-18) after strict TDD; feature doc committed 6dda58b.
- Native review blocked: `gentle-ai sync --agent pi` v3.7.0 fails verification (expects `~/.pi/agent/mcp.json` the package never ships) → assets stale → `managed_assets_outdated` stop. Known upstream: gentle-ai #5103 (fix closed 2026-09-30, unreleased > v3.7.0) and #5043 (rollback snapshot). Occurrence comment permission-blocked (no gh/token on machine); user chose report-and-continue. Fallback per unassessable plan: writer self-verification + gentle-ai-verify subagent per commit.

## Per-task evidence record

| Task | Commit | Assess tier | Outcome |
|------|--------|-------------|---------|
| T1 | 84b42b7 | unassessable (native blocked) | TDD RED 4→GREEN 14/14; full 698/699 (known baseline only); parent rerun 14/14; independent verify bg task muok4mls-6-eifi |
| T2 | 86198c2 | unassessable (native blocked) | TDD RED 12→GREEN 97/97, fix-back RED 2→101/101 (fec0::/10 full range); full 719/720 (known baseline only); parent rerun 101/101; fallback verify bg muokosdk-9-s02x |
| T3 | 8a0e861 | unassessable (native blocked) | TDD RED→GREEN; focused 8/8+1/1+12/12+2/2; full 723/724 (known baseline only); parent rerun 9/9; fallback verify bg muolhvmb-b-6cbs |
| T4 | f441c4f | unassessable (native blocked) | TDD RED observed (orphan/signal/warning) → focused 22/22+28/28+6/6+2/2 (parent rerun 58/58); full 729/730 (known baseline only); surfaces expanded by parent: Ports.res, NodeJsFileSystem.res (additive mtime), EngineLifecycle/Commit/Phase2 .resi (optional args); fallback verify bg muomqo83-h-chuw |
| T5 | 9d7ef5b | unassessable (native blocked) | TDD RED 3+6+2 → focused all green incl. real-process metachar test; full 740/741 (known baseline only); verifier verdict APPROVED (all 8 behaviors; residual register in ledger); execShellCommand grep-clean |
| T6 | 8f85e34 | unassessable (native blocked) | TDD RED→GREEN per behavior; build ZERO warnings; full 747/747 first all-green; npm pack dry-run includes dist; fallback verify muoobta9-n-m624 |
| T4-fix | 3b464fc | unassessable (native blocked) | T4 verifier finding (silent rollback failure) — RED→GREEN 29/29; full 748/748 ×3 (one transient flake once, ledger) |
| T6-fix | 6265dab | unassessable (native blocked) | T6 verifier blocker (argv-based package.json lookup dies under .bin/npx/global installs) — RED→GREEN 18/18; .bin-symlink simulation exit 0; full 751/751 |

## Next step

Feature implementation complete (six implementation work units, two verifier fixes; last full suite 751/751, zero-warning build). Main-branch merge was requested separately. Follow-ups ledger (risks for subsequent work, not claims of complete security hardening):

1. DNS-rebinding connect-time pinning (undici custom dispatcher) — residual TOCTOU, documented inline in Fetcher.res.
2. `::/96` deprecated IPv4-compatible IPv6 form classifies Public (pre-existing; non-routable legacy).
3. Windows backslash/drive-letter hook path validation and classification are closed by plan 051 (`Hooks._isPath` recognizes `\\` and drive roots; `Manifest.validateHookPath` rejects Windows-absolute forms). Windows-runtime execution remains unverified (static classification only; no Windows execution performed); allowlist still gates.
4. Symlink/file-swap TOCTOU between realpath validation and execFile (inherent window).
5. `hooks.timeout <= 0` passthrough (0 = no timeout in Node); clamp covers upper bound only.
6. Stale ExecPolicy ShellExact doc comment; dead defensive ShellExact branch; unused `execAsync` port + raw `exec` binding (removal candidates).
7. Empty output-dir mkdir when a hook is rejected post-kill-switch (benign, empty-only).
8. Rollback leaves created-but-empty dirs (audit M1, unchanged).
9. makeStagingDir fail-open + predictable name (audit M1/M2) — closed by plan 045: adapter now uses exclusive private mkdtemp; NodeJs/Os.res remains unchanged as a test-only sync convenience helper (26 test callers); plan 045's Math.random grep criterion applies to the adapter only.
10. Orphan sweep: active run idle >15 min between writes could be swept (heartbeat marker follow-up).
11. One transient full-suite flake observed once across 5 runs post-747 (never reproduced ×3; likely timing; watch in CI).
12. Readline micro-tests (buffer-before-question, ask-after-close unit variants) — behavior empirically covered by integration tests.
13. Gentle AI sync defect upstream: #5103 (fix unreleased) + #5043 — occurrence comment blocked locally (no gh/token); draft available for manual posting.

## Verdict

The scoped work units and two verifier fixes were implemented with strict TDD evidence. Native review remained blocked by the harness incident; independent verifiers approved T1/T2/T3/T5 and identified findings in T4/T6 that were fixed forward in 3b464fc and 6265dab. The last full suite passed 751/751. The residual security and reliability risks above remain open; this record is not a claim that every audit finding is resolved.
