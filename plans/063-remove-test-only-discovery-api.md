# Plan 063: Remove the test-only Discovery API (`discover`, `findByClassification`)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- src/infrastructure/discovery/Discovery.res src/infrastructure/discovery/Discovery.resi src/interfaces/cli/commands/ConfigContext.res test/Discovery_test.res test/TemplateRegistry_test.res test/EngineIntegration_test.res`
> Semantic mismatch with the excerpts below is a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

`Discovery.discover` and `Discovery.findByClassification` have zero
production callers: since plan 047's two-stage discovery, every command
uses the metadata variants (`discoverGenerators` +
`findByClassificationMeta`) to avoid reading template bodies for
unselected generators. The old eager API survives only in tests — and
`discover` silently reintroduces the eager-read behavior plan 047
eliminated whenever a test uses it. `odd/tasks/code-health-batch-2.md:11`
ruled "KEEP (separate follow-up)"; this plan is that follow-up.
Removing the dead API shrinks the module's contract and stops tests from
accidentally pinning the eager path.

Precedent to cite in the commit: plan 047 deliberately kept `discover`
exported to avoid churn in the same change ("`discover` stays exported
unchanged regardless") — the batch-2 ruling then deferred removal to
exactly this standalone follow-up.

## Current state

- `src/infrastructure/discovery/Discovery.res:358` — `let discover: (…)`
  (full-type eager discovery; reads ALL template bodies).
- `src/infrastructure/discovery/Discovery.res:383` —
  `let findByClassification: (array<generator>, string) => option<generator>`.
- `src/infrastructure/discovery/Discovery.resi:18-19` — both exports:
  ```rescript
  let discover: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, ~searchPaths: array<string>=?, unit) => promise<array<generator>>
  let findByClassification: (array<generator>, string) => option<generator>
  ```
- **Production callers: none.** `Generate.res:43,51` and
  `TemplateCopy.res:17,25` use `discoverGenerators` /
  `findByClassificationMeta`. The only `src/` mention of `discover` is a
  comment (`ConfigContext.res:6`: "generators should call
  Discovery.discover separately, AFTER validation") — stale wording to
  update.
- **Test callers to migrate:** `test/TemplateRegistry_test.res:554-557`
  (`Discovery.discover(` then `findByClassification(`),
  `test/EngineIntegration_test.res:274-282` (same pair),
  `test/Discovery_test.res:104,118,124,133` (`findByClassification`
  cases) and `:511` (usage inside a larger case).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Compile | `pnpm res:build` | exit 0 |
| Focused | `npx retest ./test/Discovery_test.res.mjs` (also TemplateRegistry, EngineIntegration) | all pass |
| Full suite | `pnpm res:test` | all pass, exit 0 |
| No stale refs | `grep -rn "Discovery.discover(\|findByClassification(" src/ test/ --include="*.res" --include="*.resi"` | only `findByClassificationMeta` remains |

## Scope

**In scope**:
- `src/infrastructure/discovery/Discovery.res` / `.resi`
- `src/interfaces/cli/commands/ConfigContext.res` (comment only)
- `test/Discovery_test.res`, `test/TemplateRegistry_test.res`, `test/EngineIntegration_test.res`

**Out of scope**:
- `discoverIn`, `discoverGenerators`, `findByClassificationMeta` (live API)
- Any production command behavior.

## Git workflow

- Branch: `chore/063-remove-test-only-discovery-api`
- Commit style: `chore(discovery): drop test-only discover/findByClassification API`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: Migrate test callers to the Meta API

- `test/Discovery_test.res:104,118,124,133`: port each
  `findByClassification` case to `findByClassificationMeta` — feed it
  `generatorMeta` fixtures (mirror how `Generate.res:51` consumes them)
  and assert on the meta (classification match / None). Keep the
  assertion INTENT (classification precedence, first-match, no-match);
  drop only what was specific to the eager `generator` shape. `:511`:
  replace the usage the same way.
- `test/TemplateRegistry_test.res:554-557` and
  `test/EngineIntegration_test.res:274-282`: replace
  `Discovery.discover(...)` + `findByClassification(...)` with
  `discoverGenerators(...)` + `findByClassificationMeta(...)` +
  (only if the test then needs bodies) `loadGeneratorTemplates(...)`
  — the plan-047 pattern the commands themselves use.

**Verify**: `pnpm res:build` → exit 0; the three focused suites pass
against the still-present old API (pure migration, no behavior change).

### Step 2: Delete the dead API

- Remove `discover` (`Discovery.res:358`) and `findByClassification`
  (`:383`) plus their `.resi:18-19` exports. If `discover` was the last
  caller of a private helper, remove that helper too (house rule:
  zero-caller items go).
- Update the stale comment `ConfigContext.res:6` to name
  `discoverGenerators`.

**Verify**: `pnpm res:build` → exit 0, no new warnings; `pnpm res:test` → all pass; grep gate clean (only `findByClassificationMeta` matches).

## Test plan

- No new tests: migrated assertions must preserve classification-logic
  coverage (Meta path), and the plan-047 counting tests elsewhere already
  pin the two-stage behavior.

## Done criteria

- [ ] `pnpm res:build` exit 0; `pnpm res:test` exit 0
- [ ] grep gate: no `Discovery.discover(`/eager `findByClassification(` references
- [ ] Classification coverage still exists via Meta tests
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- A migration reveals a test whose intent genuinely requires eager
  full-body discovery (e.g. asserts body loading side effects) — report
  it rather than distorting the test.
- Any `src/` caller appears that the audit missed (grep first: the
  Step-0 drift check plus `grep -rn "Discovery.discover(" src/`).

## Maintenance notes

- If a future feature needs eager discovery again, it should go through
  `discoverGenerators` + `loadGeneratorTemplates` explicitly, never a
  hidden eager wrapper.
- Reviewer focus: migrated tests must not lose the classification
  precedence/first-match assertions.
