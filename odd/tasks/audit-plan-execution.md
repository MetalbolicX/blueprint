# Feature: Audit Plan Execution (plans 039-053)

Execute the 15 plans from the 2026-10-01 security/performance audit in
dependency order. Per-plan source of truth: the plan files themselves and
their status rows in `plans/README.md`; this document tracks the execution
effort and records work-unit commit evidence.

## Ground rules

- One plan at a time; writes single-threaded.
- Each plan: delegate to a worker -> orchestrator review of the diff ->
  work-unit commit on the plan's branch -> record the SHA below and flip
  the `plans/README.md` row.
- Decision plans (050, 053) require maintainer rulings at their STOP steps;
  do not implement past a STOP.
- `plans/*.md` stay uncommitted unless the user asks (improve-skill
  contract from the planning phase).

## Execution order

1. 039 shell.enabled gate — DONE (commit `c3f56e0` on `fix/039-shell-enabled-gate`;
   native review approved; ruling: `enabled` default stays `false`)
2. 040 config fail-closed — DONE (commit `1a26a6f` on
   `fix/040-fail-closed-malformed-project-config`; native review approved)
3. 041 rollback accounting — DONE (commit `6ce4a1e` on
   `fix/041-failed-copy-rollback-accounting`; approved after one correction:
   review caught 2 CRITICALs, correction re-reviewed clean as
   review-4a9e2dbb69db71ee; correction-plan toolchain bug recorded)
4. 042 project hook roots — DONE (commit `7022b68` on
   `fix/042-project-hook-script-root`; native review approved,
   review-bad4830688c205c8)
5. 043 rendered conflicts — DONE (commit `0d29d85` on
   `fix/043-rendered-target-conflicts`; native review approved,
   review-1fa795419903ab12; documented RED gap)
6. 044 dry-run cleanup — DONE (commit `1def695` on
   `fix/044-dry-run-no-output-dir-deletion`; native review approved,
   review-fcd45dcf723c370c)
7. 045 staging mkdtemp — DONE (commit `bf4b1f0` on
   `fix/045-private-exclusive-staging`, stacked on 044; native review
   approved, review-8add3294190c27ea; Os.res duplicate retained by ruling)
8. 046 registry guards — DONE (commit `03e12e5` on
   `fix/046-registry-install-symlink-guards`; native review approved,
   review-fddcd0dcb308f7b0, after one escalation-caused correction)
9. 047 two-stage discovery — DONE (commit `c37a4a5` on
   `perf/047-two-stage-discovery`; native review approved,
   review-8ea6cf93ed7e6749)
10. 048 bounded fanout — DONE (commit `b375550` on
    `perf/048-bounded-discovery-fanout`, stacked on 047; native review
    approved, review-66b24f486d0860c2)
11. 049 fetch body cancel — DONE (commit `3b1972f` on
    `perf/049-cancel-abandoned-fetch-bodies`; native review approved,
    review-65cb265c314363ec)
12. 051 backslash hooks — DONE (commit `7e4c23b` on
    `fix/051-backslash-hook-paths`; escalated on false inferential findings,
    maintainer ruled hardening + fresh re-review; native review approved,
    review-2e0e2dec99cf35b0)
13. 052 timeout strings — DONE (commit `6e9e044` on
    `fix/052-timeout-duration-strings`, STACKED on 040 (`1a26a6f` — its
    fail-closed CLI path is the propagation channel); native review
    approved, review-0bd18251a2497273)
14. 050 trust-model decision — DONE (ruling: Option A honest trust;
    ADR 0001 + README landed on main as `a58a627`; prototype parked on
    spike/050-trust-model-prototype)
15. 053 architecture guard — DONE (commit `0dbee4e` on
    `chore/053-architecture-guard-parity`; Step 5 ruling: extract ports as
    target, deferred to a new plan; native review approved,
    review-de005204f84917f2)

## Evidence

**MERGED 2026-10-02**: all 14 plan branches merged to main in order
(039..053, stacks respected), --no-ff merge commits up to `88e86ef`;
final suite on merged main 802/802 exit 0; source branches deleted;
spike/050-trust-model-prototype kept parked (ADR 0001). One conflict
(test/Engine_test.res 044-vs-042 helper anchor — both kept).

| Plan | Commit | Tests |
|------|--------|-------|
| 039 | `c3f56e0` fix(exec): enforce shell.enabled on tool and script routes | 4 new gate tests; ShellExecutor 37/37; full suite 755/755 ×2; native review approved (lineage review-013684ad9fb8bab8) |
| 040 | `1a26a6f` fix(config): fail closed when project .blueprint.yaml is invalid | 3 new cases in Commands_test; focused 5/5; full suite 754/754 (after one known-flake rerun); native review approved (lineage review-01bf19a9dcd7b86a) |
| 041 | `6ce4a1e` fix(pipeline): restore failed-copy targets from their backups on rollback | RED->GREEN partial-write regression; focused 30/30 + 9/9; suite 752/752 x4; first review caught 2 CRITICALs (refuter upheld), correction re-reviewed APPROVED (lineage review-4a9e2dbb69db71ee) |
| 042 | `7022b68` fix(hooks): resolve project hooks against the invoking project root | 4 RED->GREEN hook-root cases; focused 45/45; suite 755/755 (after one known-flake rerun); native review approved (lineage review-bad4830688c205c8) |
| 043 | `0d29d85` fix(pipeline): detect conflicts on rendered target paths | 6 integration cases; suite 757/757; native review approved (lineage review-1fa795419903ab12); behavioral RED not captured (documented gap) |
| 044 | `1def695` fix(engine): skip destructive cleanup on dry runs | RED->GREEN dry-run preservation + zero-mutation; suite 752/752; native review approved (lineage review-fcd45dcf723c370c) |
| 045 | `bf4b1f0` fix(staging): create staging dirs with mkdtemp (exclusive, 0700) | RED->GREEN 0755-vs-0700; focused 27/27; suite 754/754; native review approved (lineage review-8add3294190c27ea) |
| 046 | `03e12e5` fix(registry): refuse installs shipping symlinks or provenance markers | RED->GREEN refusal cases; focused 10/10; suite 756/756; first review escalated (unknown causality), corrected + re-reviewed APPROVED (lineage review-fddcd0dcb308f7b0) |
| 047 | `c37a4a5` perf(discovery): load template bodies only for the selected generator | counting tests (selected-only reads); focused 15/15; suite 754/754 ×2 (after one known-flake failure); native review approved (lineage review-8ea6cf93ed7e6749) |
| 049 | `3b1972f` perf(fetcher): cancel abandoned redirect and error bodies | clean RED→GREEN (redirect 0→1, 500 0→3 across retries); suite 755/755 exit 0; native review approved (lineage review-65cb265c314363ec); plan's exactly-once wording corrected by ruling (500 retryable → per-attempt cancels) |
| 048 | `b375550` perf(discovery): bound template-loading concurrency and surface I/O failures | RED→GREEN (EACCES warns, peak ≤ 8 on 20-template fixture, ENOENT silent); suite 758/758 exit 0; stacked on 047 (`c37a4a5`); native review approved (lineage review-66b24f486d0860c2); first START consent expired → fresh START, no lineage leak |
| 051 | `7e4c23b` fix(hooks): classify backslash and drive-letter hook paths as paths | RED→GREEN (backslash containment + manifest rejections + no-backslash drive pin); suite 757/757 exit 0; first lineage correction_required on 3 empirically-disproven inferential findings → maintainer ruled hand-rolled predicate + fresh re-review; lineage review-2e0e2dec99cf35b0 APPROVED |
| 052 | `6e9e044` fix(config): parse documented timeout duration strings and reject invalid values | RED→GREEN (31/5 → 36/36 focused); suite 760/760 exit 0; STACKED on 040 (`1a26a6f`) after worker surfaced the caller-mismatch dependency (branch surgery, no destructive git); parse-time rejections ride 040's fail-closed CLI path; lineage review-0bd18251a2497273 APPROVED |
| 050 | `a58a627` docs(adr): record registry template trust model decision | DECISION plan — ruling Option A honest trust; ADR 0001 + README Safety on MAIN (direct docs commit per plan); prototype scan evidence: 3 example templates use `h.snakeCase(name)` helper calls; spike parked unmerged; suite 751/751 on main |
| 053 | `0dbee4e` test(guard): enforce spec patterns, .resi scans, and fail-closed directories | RED captured (guard flagged exactly the Frontmatter FFI) → Ports.path threading fix; fixture anti-vacuous tripwire; Step 5 ruling: extract ports = target, deferred to new plan; suite 753/753 exit 0; lineage review-de005204f84917f2 APPROVED |
