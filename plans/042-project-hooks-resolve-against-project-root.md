# Plan 042: Resolve project hooks against the invoking project root

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/application/engine/Engine.res src/application/engine/Engine.resi src/application/engine/EngineOrchestrator.res src/application/engine/EngineContext.res src/application/engine/EngineHooks.res src/interfaces/cli/commands/Generate.res test/Engine_test.res test/HookSecurity_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (changes hook path resolution for project-configured hooks)
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

Project-configured hooks (`.blueprint.yaml` → `hooks.pre_generate/post_generate`)
currently resolve their paths against the GENERATOR directory, not the
project. Consequences: (1) a project hook like `./scripts/pre.sh` fails with
"not found" unless the generator happens to ship a matching relative path;
(2) if the generator DOES ship one, the generator's script executes under
project-hook trust — a marked (untrusted-tier) generator can shadow a
project hook and run its own file on every generate. The trust root is
wrong: project hooks must resolve against the project that declared them.

## Current state

At `100b121`:

- `src/application/engine/EngineContext.res:7-13` —
  `buildInitialContext` sets `cwd = generatorPath` (or `"."` if missing).
  Context cwd is therefore the GENERATOR dir, not the project dir.
- `src/application/engine/EngineOrchestrator.res:51-78` (pre) and
  `:243-253` (post) — hook precedence: generator manifest hooks win
  (correctly using `scriptRoot=generator.path`); the PROJECT fallback arm is
  `(projectHook, context.cwd, outputDir)` — i.e. scriptRoot = the generator
  dir. The comments at `:52-53` even document the intended split
  ("Project hook: scriptRoot=projectRoot") — the code passes `context.cwd`
  instead.
- `src/application/engine/EngineHooks.res:5-30,55,107` — `runPreHook` /
  `runPostHook` take `~scriptRoot` (default `projectRoot` param) and pass it
  to `Hooks.run`, which resolves path-form hooks and containment-checks
  them against `scriptRoot` (`src/infrastructure/hooks/Hooks.res:74-100`).
- `src/application/engine/Engine.resi` — `Engine.run` has NO project-root
  parameter; it has `~deps: Ports.deps` (so `deps.process.cwd()` is
  available) and `~config=?`.
- CLI side: `src/interfaces/cli/commands/Generate.res` calls into the engine
  (via `Commands.res`); the CLI's own cwd is where `.blueprint.yaml` was
  loaded from (`ConfigContext.res` uses `deps.process.cwd()`).
- `test/HookSecurity_test.res` and `test/Engine_test.res` — existing hook
  tests use injected fake shell/path/fs ports; no test pins the
  project-hook scriptRoot today (that absence is why this drifted).

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Engine_test.res.mjs ./test/HookSecurity_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/application/engine/Engine.res` (+ `.resi`)
- `src/application/engine/EngineOrchestrator.res`
- `src/application/engine/EngineHooks.res` (only if the pass-through needs it)
- `src/interfaces/cli/commands/Generate.res` (to pass the new param)
- `test/Engine_test.res`, `test/HookSecurity_test.res`

**Out of scope** (do NOT touch):
- GENERATOR manifest hook resolution — `scriptRoot=generator.path` is correct
  for generator hooks; do not change it.
- `Hooks.run` internals (`_isPath`, containment) — plan 051 handles
  Windows-style paths; keep this plan's changes above `Hooks.res` where
  possible.
- `EngineContext.buildInitialContext` — its `cwd` semantics (generator dir)
  are used elsewhere (hygen-parity context building); do not repurpose it.

## Git workflow

- Branch: `fix/042-project-hook-script-root`
- Conventional commits, e.g. `fix(hooks): resolve project hooks against the invoking project root`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Pin the call sites (READ-ONLY)

`grep -rn "Engine.run\|EngineOrchestrator.run" src/ test/` — list every
caller. Also read `Generate.res`'s engine invocation to see what project
context it holds (it has `~deps`/process cwd available). Note which callers
can supply a project root and which (tests) will use a default.

**Verify**: your report lists every call site; no code changed.

### Step 2: Add `~projectRoot` to `Engine.run` and thread it

1. Add `~projectRoot: string=?` to `Engine.run` (`.resi` first). Default
   when absent: `deps.process.cwd()` (inside `Engine.run`), NOT
   `context.cwd` — the default must be a project-ish root even for callers
   that don't pass one.
2. Thread it into `EngineOrchestrator.run` (add the same optional param,
   resolving the default once).
3. In the orchestrator's PROJECT-hook fallback arms (pre `:69,73,77`; post
   `:245,249,253`), replace `context.cwd` with the resolved project root.
   `cwd` (the execution working directory, `outputDir`) stays as-is.
4. In `Generate.res`, pass `~projectRoot=deps.process.cwd()` explicitly so
   the CLI path is unambiguous.

**Verify**: `pnpm res:build` → exit 0.

### Step 3: RED→GREEN regression tests

In `test/HookSecurity_test.res` (or `test/Engine_test.res` if the wiring is
easier there — one place only, prefer where hook tests live), with fake
ports:

1. Setup: project config declares `pre_generate: "./scripts/pre.sh"`;
   project root contains `scripts/pre.sh`; the selected generator ALSO ships
   `scripts/pre.sh` (different content). Fake shell port records the
   executed path.
   - RED (current code): the GENERATOR's `scripts/pre.sh` executes.
   - GREEN (after Step 2): the PROJECT's `scripts/pre.sh` executes.
2. Project hook path that exists in the project but NOT in the generator →
   executes the project's file (today it would be "not found").
3. Project hook path outside the project root (e.g. `../outside.sh`) → still
   rejected by containment (unchanged security posture).
4. Generator manifest hook (path-form, inside generator dir) → still runs
   with `scriptRoot=generator.path` (unchanged — regression guard).

**Verify**: `npx retest ./test/Engine_test.res.mjs ./test/HookSecurity_test.res.mjs` → all pass; `pnpm res:test` → all pass (update only tests that pinned the old wrong root, with a comment `// plan 042`).

## Test plan

- The 4 cases above.
- All existing hook tests keep passing (generator hooks and allowlist
  behavior untouched).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new scriptRoot tests
- [ ] `grep -n "(projectHook, context.cwd, outputDir)" src/application/engine/EngineOrchestrator.res` returns no matches
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- `Engine.run` has non-CLI callers whose cwd is NOT the project root and
  cannot supply `~projectRoot` (surface the semantic question).
- Any existing test deliberately pins `scriptRoot=generator-dir` for
  PROJECT hooks (that would be an intentional contract this plan
  contradicts — surface it, do not silently rewrite).
- The ripple requires touching `Hooks.res` internals (out of scope).

## Maintenance notes

- After this lands, `EngineHooks`' `projectRoot` param and the new
  `~projectRoot` should be reconciled in a future cleanup (two roots flow
  through the engine; consider one explicit `runRoots` record).
- Reviewer focus: precedence (generator manifest hook wins over project
  hook) must be unchanged; only the project arm's scriptRoot changes.
- Related: plan 050 may deny manifest hooks for marked generators; that
  decision composes with (does not depend on) this fix.
