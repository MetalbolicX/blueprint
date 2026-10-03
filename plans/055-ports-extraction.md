# Plan 055: Extract application-layer infrastructure imports behind Ports

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat <writing-commit>..HEAD -- src/application/pipeline/ShellExecutor.res src/application/engine/EngineHooks.res src/application/engine/EngineOrchestrator.res src/domain/ports/Ports.res test/ArchitectureGuard_test.res test/FetchSecurity_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code; on a mismatch, treat it as
> a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MED (wide deps threading; behavior must be identical — the guard
  extension at the end proves the boundary)
- **Depends on**: plan 053 (guard at spec parity; Step 5 ruling: extract
  ports as the target state)
- **Category**: architecture (follow-up owned by the 053 Step 5 ruling)
- **Planned at**: commit `ee418f4`, 2026-10-02

## Why this matters

Plan 053's maintainer ruling recorded Ports-only consumption as the TARGET
for both layers, with application-layer module-import routing DEFERRED to
this plan. Today `ShellExecutor` references `Fetcher`, `PathSecurity`,
`ShellBuilder`, and `EnvFilter` directly (ReScript has no import statements:
these are inline module references, e.g. `Fetcher.fetch(...)`);
`EngineHooks` references `Hooks`; `EngineOrchestrator` references `Fetcher`.
Because there is no injection seam
for fetch, `FetchSecurity_test` monkey-patches `globalThis.fetch` — exactly
the fragility a port removes. After this plan: the application layer
consumes these capabilities only through `Ports` (matching the spec's
Purpose), the guard gains application-layer module-reference assertions, and
the fetch monkey-patch is deleted in favor of a fake port.

## Current state

- **Contested references** (exact, explored 2026-10-02; re-verify in Step 0):

  | Importing file | Module | Reference lines |
  |---|---|---|
  | `src/application/pipeline/ShellExecutor.res` | `Fetcher` | :75 `Fetcher.fetch(url)` |
  | `src/application/pipeline/ShellExecutor.res` | `PathSecurity` | :183, :223 `isWithinTree` |
  | `src/application/pipeline/ShellExecutor.res` | `ShellBuilder` | :286 `buildEnvFilterConfig` |
  | `src/application/pipeline/ShellExecutor.res` | `EnvFilter` | :287 `buildSafeEnv` |
  | `src/application/engine/EngineHooks.res` | `Hooks` | :41 variant, :55/:107 `run`; `.resi:14,18` type refs |
  | `src/application/engine/EngineOrchestrator.res` | `Fetcher` | :46 `clearCache()` |

- **Wider PathSecurity blast radius** (discovered during planning — the
  Step 0 STOP fired pre-execution): `Staging.res:37`,
  `TemplateRenderer.res:151,174`, `Commit.res:97,183,243` also reference
  `PathSecurity`. A guard pattern for `PathSecurity` would flag all of them,
  so the extraction MUST cover these files too (in scope below) or the
  boundary is half-done.
- **Port declaration model**: `src/domain/ports/Ports.res` is type-only;
  module types at :12-52 (`yamlParser` :29, `ejs` :33-36, `fileSystem` :38,
  `process` :52, `path` :82); aggregated in `Ports.deps` :105-114. Adapter
  convention: `src/infrastructure/adapters/NodeJsEjs.res:7` `let make`.
  Threading chain: `Cli.res:8-17` builds deps → `Router.res:168,224` →
  `Commands.res:36-45` → `Generate.res:83,91` → `Engine.res:11,21` →
  `EngineOrchestrator.res:34` (destructure) → `EnginePhases.res:13-14,49,58`
  → `Phase0.res`/`Phase1.res` → consumers.
- **Guard matcher**: `test/ArchitectureGuard_test.res` `checkLine` (:24-30)
  checks `Bindings\.[A-Z]`, `NodeJs\.[A-Z]`, `Deno\.[A-Z]`, `Ejs\.[A-Z]`,
  `@module("node:`; scanner `scanForForbiddenRefs` :32-71 already scans BOTH
  `src/domain` (:75) and `src/application` (:80) — new patterns take effect
  on the application tree the moment they are added.
- **Fetch seam root cause**: `Fetcher.res:39-40`
  `@val external _nativeFetch ... = "fetch"` (global fetch); public ops the
  application actually uses are `fetch` (ShellExecutor:75) and `clearCache`
  (EngineOrchestrator:46). `test/FetchSecurity_test.res:5-21` patches
  `globalThis.fetch` (install/restore %raw), call sites :41, :99, :124, :147
  (plus similar patches in `Fetcher_test.res:5-137`,
  `ShellExecutor_test.res:94-105`).
- **Hooks type note**: `EngineHooks` uses the `Hooks.PreGenerate` variant and
  `Hooks.hookResult` type. The port owns the types: move the hook-type
  variant + result type into `Ports` (domain-owned), and `Hooks`
  (infrastructure) consumes them — infrastructure importing domain types is
  the legal direction.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/ArchitectureGuard_test.res.mjs ./test/FetchSecurity_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/domain/ports/Ports.res` (+ `.resi`)
- `src/application/pipeline/ShellExecutor.res`
- `src/application/pipeline/Staging.res` (PathSecurity :37)
- `src/application/pipeline/TemplateRenderer.res` (PathSecurity :151,174)
- `src/application/pipeline/Commit.res` (PathSecurity :97,183,243)
- `src/application/engine/EngineHooks.res` (+ `.resi` — type refs :14,18)
- `src/application/engine/EngineOrchestrator.res`
- Deps threading (follow the `ejs` chain exactly; pin in Step 0):
  `src/domain/ports/Ports.deps` consumers — `src/interfaces/cli/Cli.res`,
  `src/interfaces/cli/Router.res`, `src/application/engine/Engine.res`,
  `src/application/engine/EnginePhases.res`, `src/application/pipeline/Phase1.res`
  (only where new members must flow)
- New adapter wiring in `src/infrastructure/adapters/` (make-functions over
  existing adapters — do NOT rewrite adapter internals)
- `test/ArchitectureGuard_test.res`, `test/FetchSecurity_test.res`, and the
  test port fakes for touched suites (`test/res/utils/TestPorts.res` if that
  is where stubs live)
- `openspec/specs/architecture-guard/spec.md` + `AGENTS.md` (final step, per
  the 053 ruling record)

**Out of scope** (do NOT touch):
- Adapter internals (`Fetcher.res`, `PathSecurity.res`, `ShellBuilder.res`,
  `EnvFilter.res`, `Hooks.res` semantics — only their consumption moves;
  `Hooks.res`/`Fetcher.res` change ONLY to consume moved types from Ports,
  nothing behavioral)
- Domain-layer code (already clean)
- Any behavior change: refactoring is mechanical (same calls through port
  members); timeout/allowlist/containment semantics unchanged

## Git workflow

- Branch: `refactor/055-ports-extraction` (from `main`)
- Conventional commits, work-unit style (see steps)
- Do NOT push or open a PR unless instructed.

## Steps

### Step 0: Pin the exact surface (READ-ONLY)

Grep and record: every contested import line and every call site of
`Fetcher.`/`PathSecurity.`/`ShellBuilder.`/`EnvFilter.`/`Hooks.` in the three
application files; the `Ports.ejs` module-type declaration as the shape
model; the deps construction chain for one existing port (CLI → Engine →
phase); FetchSecurity_test's monkey-patch lines. If the caller set exceeds
the in-scope list, STOP.

**Verify**: surface list recorded; no code changed.

### Step 1: Declare the port members (RED: guard unchanged, compile only)

Add to `Ports.res` following the existing module-type style: `Ports.fetcher`
(execute + fetch-shaped members as `Fetcher` exposes them), `Ports.shellEnv`
(EnvFilter), `Ports.pathSecurity` (already exists? pin in Step 0 — if
`Ports.path` already covers PathSecurity's needs, reuse), `Ports.shellBuilder`,
`Ports.hooks`. Expose through `Ports.deps` only where the consumers already
receive deps; where a consumer takes narrow arguments today, prefer the
narrow labeled-argument threading the codebase already uses (mirror plan
053's `~path` shape) over widening deps.

**Verify**: `pnpm res:build` → exit 0 (no consumers changed yet).

### Step 2: Move ShellExecutor behind ports (work unit 2)

Thread the port members into `ShellExecutor` (deps members or narrow labeled
args per Step 0's model — follow the `ejs` chain for whichever the file
already receives); replace `Fetcher.fetch` (:75), `PathSecurity.isWithinTree`
(:183, :223), `ShellBuilder.buildEnvFilterConfig` (:286),
`EnvFilter.buildSafeEnv` (:287) with port calls. Update its test ports to
provide the new members (fakes, not adapters).

**Verify**: `pnpm res:build`; `npx retest` on ShellExecutor's suites; full
suite green. Commit: `refactor(shell): consume fetcher/path-security/shell-builder/env-filter through Ports`.

### Step 3: Move EngineHooks + EngineOrchestrator (work unit 3)

Same shape: `Hooks.run` (:55, :107) + the `PreGenerate` variant (:41) through
a `Ports.hooks` member (types moved to Ports per the Current-state type
note); `Fetcher.clearCache` (:46) through `Ports.fetcher`.

**Verify**: build + affected suites + full suite. Commit:
`refactor(engine): consume hooks/fetcher through Ports`.

### Step 4: Extract the remaining PathSecurity references (work unit 4)

`Staging.res:37`, `TemplateRenderer.res:151,174`, `Commit.res:97,183,243` →
the same `Ports.pathSecurity`/`path` member. Thread through the existing
deps each site already receives (all are pipeline files inside the phase
chain).

**Verify**: build + affected suites + full suite. Commit:
`refactor(pipeline): consume path security through Ports in staging/render/commit`.

### Step 5: Replace the FetchSecurity monkey-patch

Rework `FetchSecurity_test` to inject a fake `Ports.fetcher` (scripted
responses) instead of patching `globalThis.fetch`; delete the patch
(install/restore %raw helpers and their 4 call sites). SSRF assertions keep
their exact semantics (each redirect/boundary case maps 1:1). If
`Fetcher_test.res:5-137`/`ShellExecutor_test.res:94-105` patches become
redundant for extracted paths, fold their replacement into the earlier work
units; only the FetchSecurity removal is required here.

**Verify**: focused FetchSecurity green; full suite. Commit:
`test(fetch-security): inject fake fetcher port instead of patching globalThis.fetch`.

### Step 6: Extend the guard (RED→GREEN tripwire)

Add application-tree patterns to `checkLine` for the extracted names
(`Fetcher\.[A-Z]`, `PathSecurity\.[A-Z]`, `ShellBuilder\.[A-Z]`,
`EnvFilter\.[A-Z]`, `Hooks\.[A-Z]` — `Ports.*` references stay legal by
construction). Extend the fixture self-test with a planted application-style
violation. Amend `openspec/specs/architecture-guard/spec.md`'s ruling record
(the deferred application-layer module-reference assertions are now
ENFORCED) and update `AGENTS.md`'s architecture arrow to
`application → domain + Ports → infrastructure`.

**Verify**: guard green against real src; planted fixture flagged; full
suite. Commit: `test(guard): assert application-layer ports-only imports (spec target reached)`.

## Test plan

- Behavior-identical refactoring: every existing suite stays green after
  each work unit (the safety net).
- Guard: new application patterns asserted; fixture tripwire extended.
- FetchSecurity: same SSRF cases via the injected fake.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0; `pnpm res:test` exits 0
- [ ] `grep -n "Fetcher\.\|PathSecurity\.\|ShellBuilder\.\|EnvFilter\." src/application/pipeline/ShellExecutor.res src/application/pipeline/Staging.res src/application/pipeline/TemplateRenderer.res src/application/pipeline/Commit.res src/application/engine/EngineHooks.res src/application/engine/EngineOrchestrator.res` returns only `Ports.`-routed calls (no bare infrastructure module references)
- [ ] `grep -rn "globalThis.fetch" test/` returns nothing
- [ ] The guard's application assertions are active and fixture-tested
- [ ] spec.md ruling record + AGENTS.md arrow updated
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Step 0's caller set exceeds the in-scope threading files (blast radius —
  surface before continuing).
- Any port member would need an ASYNC/SYNC shape mismatch vs its consumer
  (surface the design question).
- Removing the monkey-patch changes any FetchSecurity assertion's semantics
  (the fake must reproduce each case 1:1; if one cannot, surface it).

## Maintenance notes

- After this lands, update the 053 ruling record's "deferred" note to
  "reached" (done in Step 5) — the spec and code must agree.
- The four informational 053 advisories (bare built-in specifier gap,
  fixture cleanup success-only, matcher casing) are natural to fold in here
  but are NOT required by this plan — fold only if trivial.
- Domain stays the stricter boundary (it already passes; do not relax).
