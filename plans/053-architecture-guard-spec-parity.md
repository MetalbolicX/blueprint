# Plan 053: Make the architecture guard enforce its spec (and fix the violation it exposes)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- test/ArchitectureGuard_test.res src/domain/template/Frontmatter.res src/domain/ports/Ports.res openspec/specs/architecture-guard/spec.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (strengthening the guard will surface violations that must then be fixed — Frontmatter's raw node:path is one)
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

The architecture guard is the repo's only automated boundary check, and it
certifies far less than its spec requires: it scans `.res` files only (not
`.resi`), checks 3 literal substrings instead of the spec's patterns, and
passes VACUOUSLY when run from the wrong cwd (a missing `src/` directory is
"green"). Meanwhile domain code openly uses a raw `@module("node:path")`
FFI import whose comment explains it was written that way specifically to
dodge the guard's prefix patterns. A guard that misses its spec's patterns,
half the files, and fails open is worse than no guard — it manufactures
false confidence for every future refactor (including plans 042/047, which
restructure engine and discovery wiring).

## Current state

At `100b121`:

- `openspec/specs/architecture-guard/spec.md:6-17` — the spec requires:
  domain/application consume infrastructure ONLY through `Ports`; scans of
  `.res` AND `.resi`; forbidden patterns `Bindings|NodeJs|Deno\.[A-Z]`; and
  (read the spec fully — `:14-17`) missing-directory handling that FAILS
  rather than passes.
- `test/ArchitectureGuard_test.res:32-34` — the guard checks only 3 literal
  substrings (read them; they are far narrower than the spec's patterns).
- `test/ArchitectureGuard_test.res:42` — `if existsSync(dir)` style: when the
  expected directory is missing, the guard SKIPS (vacuous pass).
- `test/ArchitectureGuard_test.res:54` — the scan covers `.res` files only.
- `src/domain/template/Frontmatter.res:26-28` — raw `@module("node:path")`
  FFI in DOMAIN code, with a comment stating the import avoids the
  "infrastructure module prefix" (i.e., the guard's patterns). This is a
  live violation of the spec's Ports-only rule that the current guard
  cannot see.
- KNOWN CONTESTED AREA (do not decide it in this plan):
  `src/application/pipeline/ShellExecutor.res:75,175,269-270`,
  `src/application/engine/EngineHooks.res:55`,
  `src/application/engine/EngineOrchestrator.res:41` — application imports
  of infrastructure (Fetcher, PathSecurity, ShellBuilder, EnvFilter, Hooks).
  `openspec/specs/architecture-guard/spec.md:6` ("consume infrastructure
  only through Ports") and `AGENTS.md`'s architecture arrow
  ("application → domain + infrastructure") DISAGREE about whether these
  are legal. This plan strengthens the guard for the UNCONTESTED parts and
  STOPs at the contested question — see Step 5.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/ArchitectureGuard_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `test/ArchitectureGuard_test.res`
- `src/domain/template/Frontmatter.res` (+ `.resi` if signatures change)
- `src/domain/ports/Ports.res` (only if the path port needs a new member)
- Callers threaded in Step 3 (likely `src/infrastructure/discovery/Discovery.res`
  and manifest/config callers of `Frontmatter.parse` — pin with grep first)
- `openspec/specs/architecture-guard/spec.md` (only per the Step 5 ruling)

**Out of scope** (do NOT touch):
- The application→infrastructure imports listed above (Step 5's contested
  question — surface, do not refactor).
- Plans 042/047's restructuring areas (engine orchestrator, discovery API).
- Any `Bindings`/`NodeJs` module contents.

## Git workflow

- Branch: `chore/053-architecture-guard-parity`
- Conventional commits, e.g. `test(guard): enforce spec patterns, .resi scans, and fail-closed directories`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Strengthen the guard to its spec

In `test/ArchitectureGuard_test.res`:

1. Patterns: implement the spec's full pattern set — the forbidden
   substrings `Bindings`, `NodeJs`, plus `Deno.` followed by an uppercase
   letter, PLUS a new pattern for raw Node FFIs in domain:
   `@module("node:` (this is what Frontmatter's dodge exploits).
2. Scan `.resi` files in addition to `.res` (same pattern set).
3. Fail closed: a missing expected directory (or unreadable scan) is a
   TEST FAILURE, not a skip. If the test currently constructs its file
   list via `existsSync` guards, replace them with assertions that the
   directories exist.
4. Keep the test's existing style/conventions (it is a `.res` test using
   the repo's test helpers — read `test/res/utils/` first if helpers exist
   for file walking).

**Verify**: `npx retest ./test/ArchitectureGuard_test.res.mjs` → EXPECTED
FAILURE: the strengthened guard flags `Frontmatter.res:26-28`'s
`@module("node:path")` (record the exact failure output — this is the RED).
If it flags NOTHING, the patterns are still too narrow — STOP.

### Step 2: Fix the exposed violation — thread `Ports.path` into Frontmatter

Refactor `Frontmatter`'s raw `node:path` usage onto the `Ports.path` port:

1. Read what `Frontmatter.res:26-28` actually uses from `node:path` (likely
   `isAbsolute`/`basename`-style checks in directive validation — read the
   call sites inside the module).
2. Check `src/domain/ports/Ports.res` for an existing path-port member
   covering it (the port has `isAbsolute` per its type — verify). If the
   needed function is missing from the port, add it (mirroring the existing
   member style and the `NodeJsPath` adapter implementation).
3. Thread the needed port function(s) into `Frontmatter.parse` (new labeled
   argument(s), e.g. `~path: Ports.path`) — `Frontmatter.parse` is SYNC, so
   only sync port members qualify; if the required operation is async on
   the port, STOP (surface the sync/async mismatch).
4. Update every caller of `Frontmatter.parse` to pass the port (grep
   `Frontmatter.parse` across `src/` — expected: `Discovery.res` and
   possibly manifest/config parsing; thread the `~path` argument they
   already hold).

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/ArchitectureGuard_test.res.mjs` → passes (the guard is green against real src); `pnpm res:test` → all pass (Frontmatter behavior identical — its tests keep passing).

### Step 3: Guard self-test (fixture-based detection)

Add a guard test case that proves the guard DETECTS violations: create a
temp fixture directory (inside the test, via `os.TempDir()`-style test
helpers already used by other tests) containing a planted
`@module("node:fs")` import in a `.res` and a `NodeJs` reference in a
`.resi`, and make the guard's scan logic testable against an injected root
(extract the scan into a function taking `~root: string` — testability
refactor of the test file itself). Assert both fixture violations are
flagged. This prevents the guard from ever quietly regressing to
vacuous-green.

**Verify**: `npx retest ./test/ArchitectureGuard_test.res.mjs` → all pass, including the fixture-detection case.

### Step 4: Confirm real-src parity

With the strengthened guard green against real `src/`, record the output
(all violations found = zero after Step 2). If the strengthened patterns
flag the CONTESTED application→infrastructure imports (Step 5's list),
temporarily scope the guard's domain-only assertions to the spec's domain
rule while surfacing Step 5 — do NOT weaken the patterns to hide them;
assert them per the spec's actual scope (the spec's Ports-only rule is
about domain/application consuming infrastructure — read `spec.md:6-17`
carefully and implement exactly what it says; if the spec text itself
leaves the application-layer rule ambiguous, that ambiguity IS Step 5).

**Verify**: `pnpm res:test` → all pass; your report lists every violation class the guard now checks and real src's status for each.

### Step 5: Surface the contested spec question (STOP — maintainer ruling)

Present to the maintainer with evidence: `spec.md:6` (Ports-only
consumption) vs `AGENTS.md` (application → domain + infrastructure) vs the
live imports (`ShellExecutor.res:75,175,269-270`, `EngineHooks.res:55`,
`EngineOrchestrator.res:41`). Two rulings:

- **Fix the spec** (S): the application layer may import infrastructure
  directly; AGENTS.md's arrow is the real architecture; the guard's
  domain-only assertions stand, application assertions are dropped from the
  spec.
- **Extract ports** (L): add `Ports.fetcher`/`Ports.hooks` (the audit's
  direction finding: `FetchSecurity_test.res:5-21` monkey-patches
  `globalThis.fetch` precisely because no injection seam exists) and move
  those five imports behind Ports.

Record the ruling in `openspec/specs/architecture-guard/spec.md` (and
`AGENTS.md` if the arrow changes). If "extract ports" is ruled, that work
is a NEW plan — do not start it inside this one.

**Verify**: the spec and AGENTS.md agree with each other and with the code as guarded.

## Test plan

- Strengthened guard green against real src (after Step 2).
- Fixture-detection case (Step 3).
- Frontmatter's existing tests pass unchanged (behavior identical).
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the fixture-detection guard test
- [ ] The guard scans `.res` AND `.resi`, checks the spec's patterns plus `@module("node:`, and fails closed on missing directories (test-asserted)
- [ ] `grep -rn "@module(\"node:" src/domain/` returns no matches (the Frontmatter FFI is gone)
- [ ] The spec/AGENTS.md disagreement has a recorded ruling (Step 5) — or is explicitly escalated
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The strengthened guard flags MORE than the Frontmatter violation and the
  Step 5 contested set (an unexpected third class — enumerate it, do not
  fix it).
- Threading `Ports.path` into `Frontmatter.parse` ripples past the callers
  listed in Step 2 (surface the blast radius before continuing).
- `Frontmatter.parse` needs an ASYNC port member (sync signature conflict —
  surface the design question).
- The spec's text cannot be read as covering the application layer at all
  (then Step 5's ruling collapses to "fix the spec" — still surface it).

## Maintenance notes

- Land this BEFORE large refactors (042 engine wiring, 047 discovery API)
  if scheduling allows — the strengthened guard protects exactly those
  areas.
- If "extract ports" is ruled in Step 5, the `Ports.fetcher` spike doubles
  as the fix for the `FetchSecurity_test.res` global-monkey-patching
  pattern (the audit's grounded direction finding).
- Reviewer focus: the guard must never regain a vacuous-pass path — the
  Step 3 fixture test is the regression tripwire.
