# Plans 057-064 execution campaign

## Objective

Execute the eight improve-skill plans (057-064, planned at `b2f2670`,
committed as `82dcd93` on `plans/057-064-audit-round`) through isolated
per-plan git worktrees with parallel gentle-ai-worker executors, max 3
concurrent, zero file overlap per wave. Advisor (parent) reviews diffs,
maintains `plans/README.md` rows, and rules STOP reports.

## Constraints

- One worktree + one branch per plan; work-unit Conventional Commits on
  the plan's branch only; no push/PR/rebase; workers never edit
  `plans/README.md`.
- Wave composition honors file overlap: overlapping plans never run
  concurrently (057/058/059 share EngineLifecycle/Commit/Phase2_test;
  061 shares Phase1 files with 057).
- Workers hardlink-share `node_modules` from the main worktree
  (`cp -al`); toolchain validated (`pnpm res:build` exit 0) before
  dispatch.

## Waves

- **Wave 1 (3 concurrent, re-slotted as slots free):**
  - 058 deflake — task `muy4e00e-9-5gll` (resumed after STOP with amended
    test-local design; see plan amendment), worktree
    `../blueprint-exec-058`, branch `test/058-deflake-signal-rollback`
  - 060 docs contract — **DONE**: worker `muy49djv-4-xo8a`, advisor
    review approved (all facts verified vs `ConfigJsonParser.res:187-210`),
    committed `ffa37d9` on `docs/060-contract-sh-and-shell-enabled`
  - 062 dead exec removal — task `muy4e00e-8-4nv6` (resumed after
    surface approval: +`Hooks_test`/`Ports_test`/`Phase2_test`/`Engine_test`),
    worktree `../blueprint-exec-062`, branch `chore/062-remove-dead-shell-exact`
  - 063 Discovery API removal — task `muy4e00d-7-dota` (pulled forward
    into the free wave-1 slot), worktree `../blueprint-exec-063`,
    branch `chore/063-remove-test-only-discovery-api`
- **Queued:** 064 fetch cancel arms (free slot); 057 heartbeat (after
  058 — shared `Phase2_test.res`; 058's amendment dropped its
  `EngineLifecycle.res` edit); then 059 (requires 057), 061 (after 057).

**Integration order note:** 062's approved ripple list now includes
`Phase2_test.res`/`Engine_test.res` — integrate 058 before 062 (same
files, different regions; expect line-adjacent merges, not conflicts).

## Status

| Plan | Wave | Task | Commits | Suite | Status |
|---|---|---|---|---|---|
| 057 | 2 | muy4w1et-c-tm1v | — | — | RUNNING |
| 058 | 1 | (muy4e00e-9-5gll + amendment) | e122ac0 | 874/875 (help drift, fixed at base) | DONE |
| 060 | 1 | (muy49djv-4-xo8a) | ffa37d9 | n/a (docs) | DONE |
| 062 | 1 | (muy4e00e-8-4nv6 + 2 approvals) | b4ec25b (on 7aa2e64) | 874/874 | DONE |
| 063 | 1 | (muy4e00d-7-dota) | 3073ada | 874/875 (help drift) | DONE |
| 064 | 2 | (muy4w1eu-d-2q9b) | 8960ab9 | 879/879 | DONE |
| 059 | 3 | — | — | — | QUEUED (after 057) |
| 061 | 3 | — | — | — | QUEUED (after 057) |

## Execution discoveries

- **Baseline test drift (fixed)**: plan 056 changed `template --help` to
  `[name|dir]` without updating `CliIntegration_test`'s `[name]`
  assertion; masked by main's stale `dist/` bundle, surfaced by
  fresh-worktree builds. Fixed on the campaign base branch as `7aa2e64`
  (A/B-proven pre-existing in a pristine worktree).
- **Flake taxonomy**: two distinct known flakes — the signal-rollback
  timing flake (fixed by 058) and the LAN `RegistrySync` "opt-out/--reinstall"
  roundtrip flake (still open, LAN record's own note; reruns pass).
- **Environment**: fresh worktrees need `pnpm build` (not just `res:build`)
  before full-suite gates — `dist/main.mjs` is gitignored; also
  suite-after-build on a loaded machine can trip the LAN sync flake.
- **Process**: gentle-ai-workers never commit — parent reviews diffs and
  commits every work unit; workers request surface expansions via
  interaction prompts (3 issued: 062 ×2, 058 ×1, plus 058 build-artifact ask).

## Review protocol (advisor)

Per completed plan: read the branch diff against `82dcd93`, check the
worker's evidence (RED, gates, suite counts), update `plans/README.md`
row, record commits above. Merge/push decisions stay with the maintainer.
