# Plan 047: Discover generator metadata first; load only the selected generator's templates

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/infrastructure/discovery/Discovery.res src/infrastructure/discovery/Discovery.resi src/interfaces/cli/commands/Generate.res src/interfaces/cli/commands/TemplateCopy.res src/interfaces/cli/commands/TemplateList.res src/interfaces/cli/commands/Generator/Wizard.res test/Discovery_test.res test/Generate_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (restructures the discovery API used by every command)
- **Depends on**: none (plan 048 builds on this — land this first)
- **Category**: perf
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

`blueprint generate <name>` reads and frontmatter-parses EVERY template of
EVERY generator in every search path (project `_templates`, plus the global
registry) — then picks ONE generator by name and throws the rest away. Work
scales with the full inventory of all discovered template bytes, not with the
one generator actually used; a registry-heavy or monorepo setup pays it all
at startup of every generate. Additionally, each generator's manifest is
validated only AFTER its templates are loaded, so an invalid-manifest
generator pays a full template load before being discarded. This is the
dominant startup cost found by the 2026-10-01 audit (static analysis;
measure with the counters in Step 4).

## Current state

At `100b121`:

- `src/infrastructure/discovery/Discovery.res:158-210` (`discoverIn`) — for
  each search-path dir: `readdir` generators → for each generator dir:
  `readdir` actions → for each action dir: `readdir` files →
  `_loadTemplate` EVERY `isTemplateFile(fname)` (reads full body +
  `Frontmatter.parse`, `:25-61`) under nested `Promise.all` — and only then
  `switch await _loadManifest(...)` (`:192-198`, fail-fast contract
  documented at `:48-52`: `Ok(None)` no manifest, `Ok(Some)` valid,
  `Error` invalid → warn `"Skipping generator <name>: <reason>"` and skip).
- `src/infrastructure/discovery/Discovery.res:232-247` (`discover`) — maps
  `discoverIn` over `searchPaths` (default `["_templates", "templates", "generators"]`),
  flattens with `Array.concat` reduce (order-preserving: path order then
  generator order).
- `src/infrastructure/discovery/Discovery.res:249-265` (`findByClassification`) —
  `generators->Array.find(g => g.name == classification)` — first match in
  flattened order wins.
- `src/interfaces/cli/commands/Generate.res:37-42` — `discover(...)` then
  `findByClassification(generators, name)` → ONE generator.
- `src/interfaces/cli/commands/TemplateCopy.res:13-15` — same
  discover-then-find pattern for a single lookup.
- Full-inventory consumers that must keep working unchanged:
  `TemplateList.res` and `Generator/Wizard.res` (grep
  `Discovery.discover` in Step 1 to confirm the full caller list).
- `test/Discovery_test.res` — existing tests use injected fake
  `fs/path/yamlParser` ports (assert warning texts and discovery results);
  model new tests on them.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Discovery_test.res.mjs ./test/Generate_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/discovery/Discovery.res` (+ `.resi`)
- `src/interfaces/cli/commands/Generate.res`
- `src/interfaces/cli/commands/TemplateCopy.res`
- `test/Discovery_test.res`, `test/Generate_test.res` (and the callers'
  existing tests if they pin the old call shape)

**Out of scope** (do NOT touch):
- `TemplateList.res` / `Wizard.res` — they legitimately need the full
  inventory; keep them on `discover` (unchanged behavior).
- Error-warn behavior for invalid manifests (preserve messages verbatim).
- Bounding concurrency / surfacing I/O errors — plan 048 (land after this).
- Search-path precedence and default paths — unchanged.

## Git workflow

- Branch: `perf/047-two-stage-discovery`
- Conventional commits, e.g. `perf(discovery): load template bodies only for the selected generator`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Pin the callers (READ-ONLY)

`grep -rn "Discovery.discover\|findByClassification\|discoverIn" src/ test/`
— record the full caller list and which ones need the full inventory vs a
single lookup. Anything not on the Generate/TemplateCopy single-lookup list
stays on `discover`.

**Verify**: caller list recorded; no code changed.

### Step 2: Split the API in `Discovery.res`

Add (keep `discover`/`findByClassification` exported and unchanged):

1. `type generatorMeta = {name: string, path: string, manifest: option<Manifest.manifest>}`
   (module-level type, following the file's existing record style).
2. `let discoverGenerators: (~fs, ~path, ~yamlParser, ~searchPaths=array<string>=?, unit) => promise<array<generatorMeta>>`
   — the same walk as `discoverIn` BUT per generator: `readdir` the
   generator dir's ACTIONS ONLY to confirm it is a generator (presence of
   any action subdirectory is the current de-facto test — replicate exactly
   what `discoverIn`'s `stat`/isDirectory checks do, no template reads), then
   `await _loadManifest(...)` FIRST (fail-fast: same
   `"Skipping generator <name>: <reason>"` warn-and-skip on `Error`),
   emitting `{name, path, manifest}`. Order: same as today (search-path
   order, then readdir order).
3. `let loadGeneratorTemplates: (~fs, ~path, string) => promise<array<Template.template>>`
   — the action-dir walk + `_loadTemplate` loop for ONE generator path
   (extract the body of today's per-generator template loading into this
   function so `discoverIn` and it share it, or duplicate minimally if
   extraction fights the existing shape — prefer extraction).
4. `let findByClassificationMeta: (array<generatorMeta>, string) => option<generatorMeta>`
   — same first-match semantics.

Update `Discovery.resi` with the new exports following its existing style.

**Verify**: `pnpm res:build` → exit 0.

### Step 3: Rewire the single-lookup callers

`Generate.res:37-42` and `TemplateCopy.res:13-15`:
`discoverGenerators(...)` → `findByClassificationMeta(metas, name)` → on
`Some(meta)`, `loadGeneratorTemplates(~fs, ~path, meta.path)` → build the
`generator` value the downstream code expects (same record shape
`discover` produced — `{name, path, templates, manifest}`). On `None`, the
existing not-found error path applies unchanged. Keep every user-visible
message identical.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Discovery_test.res.mjs ./test/Generate_test.res.mjs` → all pass except tests that pinned the old call shape (update with `// plan 047` comments); `pnpm res:test` → all pass.

### Step 4: Counting tests (the measurement)

In `test/Discovery_test.res` (fake fs port records `readFile` calls):

1. Fixture: 3 generators × 2 templates each; select generator B. Assert:
   template-body reads = B's templates ONLY (fake fs's recorded paths), and
   manifest reads ≤ 3 (all manifests are metadata-stage, allowed).
   (RED against the old code if run before rewiring: 6 template reads.)
2. Invalid-manifest generator among 3 → the same
   `"Skipping generator <name>: <reason>"` warning fires during metadata
   discovery, selection still works for a valid one, and the invalid one's
   template files are NEVER read (fail-fast ordering — RED today: templates
   load before the manifest check).
3. Precedence: same generator name in `_templates` and a later path →
   first-path entry wins (assert `path` of the selected meta).
4. End-to-end generate on the selected generator produces the same result
   as before (regression guard; existing Generate tests cover this).

**Verify**: `npx retest ./test/Discovery_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The 4 cases above; model fixtures/fakes after existing `Discovery_test.res`.
- Full-suite gate (TemplateList/Wizard keep passing on `discover`).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new counting tests
- [ ] The counting test asserts unselected generators' template files are never read (fake-fs evidence)
- [ ] Invalid-manifest warning text is byte-identical to today's
- [ ] `TemplateList`/`Wizard` behavior unchanged (their tests pass untouched)
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- A third single-lookup caller exists with different needs (e.g. needs
  templates AND all metadata) — surface before rewiring it.
- `generator`'s record shape is consumed positionally somewhere that a
  meta+templates reconstruction cannot satisfy.
- Extraction of the shared template-walk would require changing
  `_loadTemplate`'s contract (skip_if/frontmatter warnings).

## Maintenance notes

- Plan 048 (bounded concurrency + surfaced I/O errors) applies its changes
  to THIS shape — execute 048 after this lands.
- `discover` (full) remains for list/wizard; if those ever get slow, the
  same meta-first split can serve them lazily.
- Rejected alternative (do NOT reintroduce): EJS compile caching — every
  template renders once per invocation; there is no repeated-work gap.
- Rejected alternative: caching `PathSecurity` root realpaths across
  renders — the roots are mutable security boundaries; no cross-request
  path-check caching.
