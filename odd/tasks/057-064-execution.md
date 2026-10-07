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
| 057 | 2 | (muy4w1et-c-tm1v) | ac6c125 | 881/881 | DONE |
| 058 | 1 | (muy4e00e-9-5gll + amendment) | e122ac0 | 874/875 (help drift, fixed at base) | DONE |
| 060 | 1 | (muy49djv-4-xo8a) | ffa37d9 | n/a (docs) | DONE |
| 062 | 1 | (muy4e00e-8-4nv6 + 2 approvals) | b4ec25b (on 7aa2e64) | 874/874 | DONE |
| 063 | 1 | (muy4e00d-7-dota) | 3073ada | 874/875 (help drift) | DONE |
| 064 | 2 | (muy4w1eu-d-2q9b) | 8960ab9 | 879/879 | DONE |
| 059 | 3 | (muy5ofpg-h-r7ea + readdir ruling; orig muy5ewp9-g-s4me) | 3be0c1b | 885/885 | DONE |
| 061 | 3 | (muy5ofph-i-laf5 + Phase0_test approval) | cbc90d6 | 883/883 | DONE |

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

## Final state (2026-10-05)

Campaign COMPLETE: 8/8 plans executed by gentle-ai-workers, diff-reviewed
and committed by the advisor. Branch inventory (all exec worktrees remain
registered for integration):

| Branch | Tip commit | Base |
|---|---|---|
| plans/057-064-audit-round (campaign) | 552eb6c | 82dcd93 |
| fix/057-orphan-sweep-heartbeat | ac6c125 | 7aa2e64 |
| test/058-deflake-signal-rollback | e122ac0 | 82dcd93 |
| fix/059-rollback-empty-dir-residue | 3be0c1b | ac6c125 |
| docs/060-contract-sh-and-shell-enabled | ffa37d9 | 82dcd93 |
| refactor/061-render-to-once | cbc90d6 | ac6c125 |
| chore/062-remove-dead-shell-exact | 42a51d2 (b4ec25b + plan-outcome note) | 7aa2e64 |
| chore/063-remove-test-only-discovery-api | 3073ada | 82dcd93 |
| fix/064-cancel-fetch-body-failure-arms | 8960ab9 | 7aa2e64 |

Campaign-side commits: 7aa2e64 (baseline LAN help-test drift fix),
b4cab8e + 552eb6c (bookkeeping), plus this doc's follow-up rows.

Integration guidance: branches are pairwise-disjoint except the known
adjacencies — 058 before 062 (both touch Phase2_test), 057 before
059/061 (already their bases). Suggested order onto an integration base
(campaign base 7aa2e64 or main): 058 → 062 → 063 → 060 → 064 → 057 →
059 → 061. Merge/push/pull-request remain the maintainer's decision.

RDD was ON (global) at close; the native review gate is entered
separately, candidate by candidate, per the review contract.

## Native review receipts (2026-10-05, reduced-scope per-commit candidates)

| Plan | Lineage | Outcome | Consumed |
|---|---|---|---|
| 059 | review-33a1c5635f529122 | APPROVED + acked, burned | beea56db |
| 057 | review-dc4de0b4dde0fa61 | APPROVED + acked, burned | 0098314f |
| 058 | review-9664febc1f4ecfc8 | APPROVED + acked, burned | dea21310 |
| 061 | review-2f640ba3bd9a1461 | APPROVED + acked, burned | ecb957f5 |
| 063 | review-0c0df719c4b3468a | APPROVED + acked, burned | c68e2248 |
| 064 | review-5e519c1aa8434d28 | APPROVED + acked, burned | 2e8e90f7 |
| baseline (`test/CliIntegration` fix + campaign docs, range `82dcd93..ac5db4b`) | review-53e9eba2a82ba875 | APPROVED + acked, burned | 8df1b774 |
| 062 | review-b6974bd8535894d5 | APPROVED + acked, burned (re-review after v1 escalated; stacked `42a51d2` plan-outcome note, no history rewrite) | 8b6c3c74 |
| ~~062 v1~~ | review-8b0f4ca4ed414c05 | terminal `escalated` — permanent audit record (abandon/reclaim refused; blocks only its own dead identity) | — |
| 060 | — | skipped (docs-only, sanctioned trivial-passive-documentation skip) | — |

Learnings: policy-derived base spans the whole LAN history → every START
used explicit baseRef=parent (reduced scope) after the provider's
lens_context_budget_exceeded remediation; one consent binding expired
mid-batch (fresh START per provider instruction); one forecast
acknowledgement failed natively → bound status → escalated state.
Escalation resolution (2026-10-05): terminal escalated authority refuses
`review abandon` (terminal) and `review reclaim` (holds admitted lens
artifact); resolved via the change-candidate-content remedy — stacked
plan-outcome note commit `42a51d2` on `chore/062` and re-reviewed the
superset range as `review-b6974bd8535894d5` → approved, burned.
The dead identity's authority record stands as a persisted audit artifact.
The main worktree's three prior-session untracked files forced an
intended-untracked selection that conflicted with reduced baseRef →
baseline reviewed from a clean detached worktree at `ac5db4b` instead.

## Integration to main (2026-10-05, LAN excluded)

`main` was LAN-free (`0b94987`), while the campaign branch sat on top of
`feat/lan-registry` (`b2f2670`, 11 LAN commits) — so direct merges would
have dragged the LAN feature in. Delivered instead by cherry-picking each
plan's commits onto `main` (15 commits, 56 files, +2654/−273; build clean,
suite **826/826** — 885 campaign-side minus 59 LAN tests).

Excluded as LAN-dependent: `7aa2e64` (help-text `[name|dir]` test fix —
on LAN-free `main` the original `[name]` expectation is correct again).

Conflict resolutions (rule: main's content + only the plan's delta):
- `72a9911` (060): LAN's config-reference rework was the diff host — kept
  main's sections, added 060's shell-subkeys table + allowlisted note to
  api-reference; dropped the LAN-authored Effective-keys paragraph edit in
  quick-reference (host text does not exist on main).
- `ff78198`/`f76baf3`/`13b798b` (docs picks): dropped the LAN 056 row from
  plans/README.md at each alignment conflict.

Campaign SHA → main SHA mapping (review receipts bind to the campaign
identities; these are the integrated equivalents):

| Plan | Campaign SHA (branch) | Main SHA |
|------|------------------------|----------|
| 058 | e122ac0 (test/058) | `47ecac3` |
| 062 | b4ec25b + 42a51d2 (chore/062) | `bfd8308` + `52e4fed` |
| 063 | 3073ada (chore/063) | `656ea46` |
| 060 | ffa37d9 (docs/060) | `72a9911` |
| 064 | 8960ab9 (fix/064) | `4064c4e` |
| 057 | ac6c125 (fix/057) | `02f3b81` |
| 059 | 3be0c1b (fix/059) | `31dc566` |
| 061 | cbc90d6 (refactor/061) | `a877865` |
| plans docs | 82dcd93 | `ff78198` |
| bookkeeping | b4cab8e / 552eb6c / e8f3c02 / ac5db4b / bdcfa13 | `64e16d4` / `86af5da` / `f76baf3` / `13b798b` / `bbf2032` |

`feat/lan-registry` (`b2f2670`) remains unmerged by explicit user decision;
the campaign branch `plans/057-064-audit-round` (`bbf2032`-equivalent
`bdcfa13`) stays as the LAN-based historical record.
