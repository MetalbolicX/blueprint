# Plan 061: Render each `to:` directive exactly once and thread it through the pipeline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/application/pipeline/Phase0.res src/application/pipeline/Phase1.res src/application/pipeline/TemplateRenderer.res src/application/engine/EnginePhases.res src/application/engine/EngineOrchestrator.res test/Phase0Integration_test.res test/Phase1_test.res test/TemplateRenderer_test.res`
> Semantic mismatch with the excerpts below is a STOP condition;
> line-number-only drift is benign.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (pipeline data-flow change; guarded by fallback + full conflict-test suite)
- **Depends on**: none (recommended after 057/059 to avoid test churn)
- **Category**: refactor
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

Every `to:` frontmatter directive is EJS-rendered **twice** per run: once
in Phase 0 for conflict detection and again in the renderer for the
actual write. This is documented as a known issue
(`plans/043-conflict-detection-on-rendered-targets.md:194-197`: "Known
double-evaluation: `to:` renders twice (Phase0 + renderer). Pure
interpolation makes this harmless; if a single-resolve refactor is ever
done (resolve once in Phase0, thread forward), it must preserve both
conflict detection and provenance-gate ordering"). It is not merely
wasteful: the two sites build their attribute dictionaries differently
(Phase 0 merges base context + prompt answers; the renderer rebuilds
from `ctx.nameVariants` + stringified `ctx.attributes`), so any
non-pure or context-sensitive template can make the conflict check
examine a DIFFERENT path than the one actually written — the exact
class of bug plan 043 was closing. Resolving once in Phase 0 and
threading the resolved path forward removes the divergence class and
halves the render cost.

## Current state

- **Site A — Phase 0 (conflict detection):**
  `src/application/pipeline/Phase0.res:20-28`:
  ```rescript
  let detectRenderedConflicts: (~templates, ~outputDir, ~force, ~ejs, ~attributes, ~fs, ~path, ~pathSecurity) => promise<result<array<conflictFile>, string>>
  ```
  render call at `Phase0.res:58`:
  `switch TemplateRenderer.renderTargetPath(~to, ~ejs, ~attributes)`.
  Attributes built in `Phase0.run` (`:137-141`): `baseContext` from
  `context.attributes` merged with prompt `resolvedAttributes` →
  `mergedAttributes`.
- **Site B — renderer (actual write):**
  `src/application/pipeline/TemplateRenderer.res:221-223` inside `render`:
  `->Option.map(d => resolveTargetPath(~ejs, d, context))`;
  `resolveTargetPath` (`:31-52`) builds attributes from
  `ctx.nameVariants` (`name/Name/names/Names`) + `ctx.attributes`
  (Scalar/Values stringified) → `renderTargetPath(~to, ~ejs, ~attributes)`
  (`:16-29`) → `ejs.renderString`.
- **Shared primitive:** `TemplateRenderer.renderTargetPath` (`:16`) —
  both paths already funnel through it.
- **Data flow / threading seam:** `Phase0.run` returns
  `{resolvedAttributes, conflicts}` (`Phase0.res:12-15`) →
  `EnginePhases.runPhase0` → `EngineOrchestrator.res:158`
  `EngineContext.buildMergedContext(~promptAnswers=p0.resolvedAttributes)`
  → `EngineOrchestrator.res:169` `runPhase1(~mergedContext)` →
  `Phase1.run(~context=mergedContext)`. Resolved target paths are
  currently **discarded** after conflict checks (only `conflictFile`
  pairs survive). `Phase1._prepareTemplate` (`Phase1.res:47`) calls
  `TemplateRenderer.render`.
- **Advisory note (must preserve):** the provenance advisory
  (`TemplateRenderer.res:237-246`, `Console.warn` on
  `hasProvenance && EjsSafety.isUnsafe(resolvedBody)`) inspects the
  template BODY, not the path — it must keep firing regardless of
  whether the path came pre-resolved. (The old hard gate is gone; plan
  054 made it advisory.)
- **Tests pinning behavior:** Phase0 path — `test/Phase0Integration_test.res`
  `:207` (prompt-attribute target detection), `:311` (render errors fail
  before writes), `:355` (NoAll skips), `:376` (yes overwrites), `:397`
  (force overwrites), `:418` (duplicate targets share decision), `:152`,
  `:265`. Renderer path — `test/TemplateRenderer_test.res:4` suite
  (`:12` EJS error surfaces, `:24` valid path resolves),
  `test/Phase1_test.res:30/:46/:61` (`resolveTargetPath` cases).

Conventions: `result<'a, string>` errors; injected `Ports` (`ejs`,
`fs`, `path` are already injected everywhere here); optional labeled
args use `=?` defaults to keep old callers compiling (house pattern —
see `~projectRoot` in plan 042's Engine change).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0 |
| Focused | `npx retest ./test/Phase0Integration_test.res.mjs` (also `Phase1_test`, `TemplateRenderer_test`) | all pass |
| Full suite | `pnpm res:test` | all pass, exit 0 |

## Scope

**In scope**:
- `src/application/pipeline/Phase0.res` / `.resi`
- `src/application/pipeline/Phase1.res` / `.resi`
- `src/application/pipeline/TemplateRenderer.res` / `.resi`
- `src/application/engine/EnginePhases.res`, `EngineOrchestrator.res` (and the module owning `buildMergedContext` / merged-context type — locate it via `EngineOrchestrator.res:158`)
- `test/Phase0Integration_test.res`, `test/Phase1_test.res`, `test/TemplateRenderer_test.res`

**Out of scope**:
- Conflict DECISION semantics (y/n/s/a prompts, force, UnlessExists)
- The advisory warning itself (`:237-246` stays byte-identical in behavior)
- `renderTargetPath` internals; EJS safety checks; TemplateCopy flow

## Git workflow

- Branch: `refactor/061-render-to-once`
- Commit style: `refactor(pipeline): resolve to: once in Phase0 and thread to the renderer`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: RED — prove the double render deterministically

New test (e.g. in `test/Phase0Integration_test.res`): run the full
Phase0→Phase1 flow with an injected `ejs` stub (extend the
`TestPorts`/fixture pattern used by existing integration tests) that
COUNTS invocations of `renderString` whose input is the template's `to:`
string. One template, one run.

- Assert `toRenderCount == 1`.
- Observe RED: today it is `2`.

Second RED assertion (the divergence proof): make the stub return
`"first.txt"` on the first call and `"second.txt"` on later calls.
Assert the written file's path equals the path Phase0 conflict-checked
(observable via the conflict fixture or the written output): today the
write goes to `second.txt` while Phase0 examined `first.txt` — the bug
in miniature.

**Verify**: `npx retest ./test/Phase0Integration_test.res.mjs` → both new assertions FAIL. Record RED.

### Step 2: Collect resolved targets in Phase 0

- In `Phase0.detectRenderedConflicts`, alongside the existing per-template
  conflict work, collect `resolvedTargets: array<{sourcePath, targetPath}>`
  for every `To` directive that rendered `Ok` (also collect render
  ERRORS' `sourcePath` so the renderer can re-error faithfully — or rely
  on Phase 0's existing fail-closed behavior for render errors; keep the
  existing `:311` semantics: errors fail the run before writes).
- `Phase0.run` returns `{resolvedAttributes, conflicts, resolvedTargets}`
  (extend the record; update `.resi`).

**Verify**: `pnpm res:build` → exit 0; existing Phase0 tests pass (new field is additive).

### Step 3: Thread through the engine context

- `EnginePhases.runPhase0` / `EngineOrchestrator.res:158-169`: carry
  `resolvedTargets` into the merged context (or pass alongside it to
  `runPhase1`). Prefer an optional field with a sane default so
  standalone `Phase1.run` callers (tests) compile unchanged.

**Verify**: `pnpm res:build` → exit 0.

### Step 4: Prefer the pre-resolved path in the renderer

- `Phase1.run` / `_prepareTemplate` / `TemplateRenderer.render`: accept
  `~preResolvedTargets` (keyed by `sourcePath`). In `render`'s `To` arm
  (`:221-223`): if a pre-resolved target exists for this template's
  `sourcePath`, use it verbatim and SKIP `resolveTargetPath`; otherwise
  render as today (fallback for standalone callers).
- The body-resolution + advisory path (`:237-246`) runs exactly as
  before — only the target-path resolution is short-circuited.

**Verify**: `npx retest ./test/Phase0Integration_test.res.mjs` → Step-1 tests GREEN (`toRenderCount == 1`, written path == checked path).

### Step 5: Regression gate

**Verify**: `npx retest ./test/Phase1_test.res.mjs` and
`npx retest ./test/TemplateRenderer_test.res.mjs` → all pass;
`pnpm res:test` → all pass, exit 0 (the full conflict suite
`:152`–`:418` must be untouched-green).

## Test plan

- New: counting-ejs test (1 render per `to:`) + divergence test
  (deterministic stubbed renders prove path identity).
- Existing: all Phase0Integration / Phase1 / TemplateRenderer tests
  green unchanged — they pin conflict semantics and the fallback path.

## Done criteria

- [ ] RED evidence recorded (Step 1)
- [ ] `pnpm res:test` exits 0
- [ ] `to:` renders exactly once per run in the new test
- [ ] Advisory warning behavior unchanged (`TemplateRenderer_test` provenance suite green)
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Threading requires changing modules beyond those listed in Scope
  (e.g. the merged-context type forces edits in unrelated commands).
- Any existing conflict test changes behavior (decision flow, prompts,
  force, UnlessExists) — the refactor must be invisible to them.
- The advisory warning would need to move or re-order to make the
  threading work (plan 043 constraint; report instead).

## Maintenance notes

- Fallback retained deliberately: `Phase1`/`TemplateRenderer` remain
  usable standalone (tests, future callers) by rendering on miss.
- Plan 043's maintenance note can be retired when this lands — update
  that plan file's note only if the maintainer asks.
- Reviewer focus: the `sourcePath` keying (templates are unique by
  source path in a run) and that render ERRORS still fail in Phase 0
  before any write.
