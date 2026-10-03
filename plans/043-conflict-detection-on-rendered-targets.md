# Plan 043: Detect and resolve file conflicts on rendered target paths

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/application/pipeline/Phase0.res src/application/pipeline/Phase0.resi src/application/pipeline/TemplateRenderer.res src/application/pipeline/TemplateRenderer.resi src/application/conflicts/ConflictRunner.res test/Phase0Integration_test.res test/Phase0_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (changes conflict-detection timing and decision matching)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

Phase0 checks file conflicts against the RAW `to:` frontmatter value, but the
renderer later evaluates that value through EJS and matches user decisions
against the RENDERED path. Every templated destination (the common case —
e.g. `_templates/react-component/new/Component.tsx.ejs.t:2` uses
`to: <%= name %>.tsx`) therefore bypasses conflict detection: an existing
file at the rendered target is silently overwritten (with backup) instead of
prompted, and a user's "no" decision on the raw path never matches the
rendered path, so it cannot skip. Conflict prompts only ever fire for
static, un-templated `to:` values.

## Current state

At `100b121`:

- `src/application/pipeline/Phase0.res:17-73` — `detectConflicts` filters
  templates with a `To` directive (excluding `unless_exists`), then for each
  pair checks `fs.fileExists(path.join(outputDir, targetPath))` where
  `targetPath` is the RAW directive value (`:47-64`). Conflicts are
  collected as `{sourcePath, targetPath: fullTarget}`.
- `src/application/pipeline/Phase0.res:75-135` — `run` resolves prompts
  FIRST (`resolve(~io, ~ejs, ~prompts, ~force, ~baseContext)` — answers land
  in `resolvedAttributes`), and only THEN calls `detectConflicts`
  (`:116-118`). It receives `~ejs` already. `detectConflicts` itself takes
  no ejs/context today.
- `src/application/pipeline/TemplateRenderer.res:47` — `resolveTargetPath`
  renders the `To` value via `ejs.renderString` (same inputs: the merged
  render context). Invoked at `:221-229` BEFORE the provenance gate and body
  render.
- `src/application/pipeline/TemplateRenderer.res:176-180` (inside
  `stageAndValidate`) — conflict decisions are matched against the RENDERED
  `targetPath`.
- `src/application/conflicts/ConflictRunner.res:29-60` — decisions are
  built from the conflict entries Phase0 produced (`--force` → all
  overwrite=true without prompting).
- `test/Phase0Integration_test.res:123` — the only conflict integration
  test uses a STATIC `To("Hello.tsx")`; nothing covers templated targets.
- Attribute vocabulary for rendering: prompt answers + CLI + hook
  attributes, stringified — see `Phase0.run`'s `baseContext` construction
  (`:96-106`) and `Context.toRenderContext` (used by the renderer).

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Phase0Integration_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/Phase0.res` (+ `.resi` if signatures are exported there)
- `src/application/pipeline/TemplateRenderer.res` (+ `.resi`)
- `test/Phase0Integration_test.res` (primary), `test/Phase0_test.res` if it exists

**Out of scope** (do NOT touch):
- `ConflictRunner.res` / `ConflictResolver.res` — they consume whatever
  conflict entries Phase0 emits; no change needed there.
- Prompt resolution order (answers must exist before `to:` can render —
  already the case).
- The provenance/EJS-safety gate (plan 050 owns that design space).
- `force:` frontmatter consumption — related but separate (see Maintenance
  notes; do not fold it in).

## Git workflow

- Branch: `fix/043-rendered-target-conflicts`
- Conventional commits, e.g. `fix(pipeline): detect conflicts on rendered target paths`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Share one target-path resolver

Export `resolveTargetPath` from `TemplateRenderer.res` (it is currently a
local helper around `:47`; add it to `TemplateRenderer.resi`). It must take
exactly the inputs Phase0 can supply: the directive, the ejs port, and a
plain `dict<string>` of attributes (prompt answers merged over base
attributes — build it the same way `Phase0.run` builds `baseContext`, plus
`resolvedAttributes` overlaid). Keep the renderer's own call sites
unchanged in behavior.

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Render targets in `detectConflicts`

Change `detectConflicts` to accept `~ejs` and the merged attribute dict
(prompt answers + base context — both available in `run` at call time
`:116-118`). For each `To` directive:

1. Resolve the target via the shared `resolveTargetPath`. On render error →
   propagate `Error("Failed to render 'to' path in template <sourcePath>: <msg>")`
   (fail closed — Phase0.run's error handling already wraps detectConflicts
   callers; check `run`'s return type and thread `result` if needed).
2. Existence-check and conflict-report the RESOLVED path
   (`fullTarget = path.join(outputDir, resolvedTarget)`).

Keep `unless_exists` exclusion and `--force` plumbing exactly as-is.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Phase0Integration_test.res.mjs` →
static-path tests still pass (unchanged behavior for static `To`).

### Step 3: Decision matching parity

Confirm `stageAndValidate` (`TemplateRenderer.res:176-180`) matches decisions
by the same resolved path (it already renders the target itself via
`resolveTargetPath` — with Step 1's shared helper the two call sites now
produce identical strings). If any normalization differs (join order,
trailing separators), fix by construction in the shared helper, not by
string-munging at the match site.

**Verify**: `pnpm res:build` → exit 0.

### Step 4: RED→GREEN tests

In `test/Phase0Integration_test.res` (model after the existing static-target
test at `:123`), with fake fs/io ports:

1. Template with `To("<%= name %>.tsx")`, attribute `name="Hello`, target
   file `Hello.tsx` ALREADY exists → a conflict IS detected and the bulk
   prompt fires (RED today: silently no conflict).
2. User answers "no" (`NoAll`) → template is SKIPPED (decision matches the
   rendered path; no write to `Hello.tsx`).
3. User answers "yes" → file overwritten (with backup), as today.
4. `--force` with an existing rendered target → overwrite without prompt
   (regression guard for the force path through ConflictRunner).
5. `To` render error during conflict detection (bad expression) → run
   returns `Error` naming the template; no writes.
6. Two templates resolving to the SAME rendered target with an existing file
   → both appear in the conflict list (or are deduped) — assert whichever
   the implementation produces, as long as the decision applies to BOTH
   (dedup by resolved `fullTarget` is the cleaner choice; if you dedup,
   assert one prompt entry).

**Verify**: `npx retest ./test/Phase0Integration_test.res.mjs` → all pass; `pnpm res:test` → all pass (update only tests that pinned raw-path conflicts, with `// plan 043` comments).

## Test plan

- The 6 cases above in `test/Phase0Integration_test.res`.
- Full suite: `Phase2`/`TemplateRenderer` conflict tests keep passing
  (decision matching is unchanged for static targets).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new templated-target cases
- [ ] `grep -n "resolveTargetPath" src/application/pipeline/Phase0.res` shows the shared resolver in use
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Prompt answers cannot be stringified into the attribute dict at conflict
  detection time (they can — `resolvedAttributes` is a `dict<string>` — but
  if the render context needs structured values, surface the mismatch).
- `stageAndValidate`'s decision matching depends on something beyond the
  resolved path (e.g. sourcePath keys) — surface before changing matching.
- Deduplicating same-rendered-target conflicts would break the
  per-source-prompt UX in `ConflictRunner`'s Select mode.

## Maintenance notes

- Known double-evaluation: `to:` renders twice (Phase0 + renderer). Pure
  interpolation makes this harmless; if a single-resolve refactor is ever
  done (resolve once in Phase0, thread forward), it must preserve both
  conflict detection and provenance-gate ordering (plan 050).
- Related open finding (NOT in this plan): frontmatter `force:` is parsed
  (`src/domain/template/Frontmatter.res:103-104`, typed at `Template.res:13`,
  promised by `docs/quick-reference.md:44` and `docs/api-reference.md:96`)
  but has ZERO consumers. If conflict UX is being revisited, plan its
  consumption or its removal from docs separately.
- Commit's own dedup (`Commit.res:81-89`, first-wins by target path) now
  becomes the last line of defense for duplicate rendered targets — leave
  it in place.
