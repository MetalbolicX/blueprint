# Plan 032: `create-res-project` post-hook + structured JSON I/O + verify follow-ups

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat dc6cefd..HEAD -- src/domain/manifest/Manifest.res src/infrastructure/discovery/Discovery.res src/application/engine/EngineOrchestrator.res examples/create-res-project/`
> Note: plans 030 + 031 are applied but uncommitted in the working tree. The
> SHA `dc6cefd` is the last commit; the in-scope files already contain
> uncommitted modifications from those plans. Compare against the live working
> tree, not the committed SHA.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/031 (verified PASS, archived; changes in working tree)
- **Category**: feature
- **Planned at**: commit `dc6cefd` (working tree), 2026-08-05

## Why this matters

`blueprint generate create-res-project <name>` currently produces three files
(`src/Main.res`, `rescript.json`, `rolldown.config.mjs`) but the result is
**not a runnable ReScript project** — no ReScript dependency, no npm scripts,
no engine requirement. The user must manually run install commands and edit
`package.json`. This plan closes that gap with a controlled post-hook that
mutates `package.json` via structured JSON file I/O (NOT shell interpolation,
NOT `pnpm add`).

**Design choice (Option B from the post-hook analysis)**: mutate
`package.json` only; do NOT auto-install dependencies. Rationale:
- Blueprint's Phase2 rollback restores committed files; `package.json` is
  pre-existing (not in the committed set), so a failed `pnpm add` would leave
  a half-mutated lockfile that rollback cannot fix.
- Mutating `package.json` with pinned versions is deterministic and
  rollback-safe at the script level (in-script backup + atomic write).
- The user runs `pnpm install` once — same as every other scaffolded project.

This plan also closes four follow-ups flagged by sdd-verify (#3056):
1. Discovery test asserting the generator carries both hook paths.
2. Manifest load-guard for missing hook files.
3. Design doc update for ReScript nested-switch syntax reality.
4. End-to-end smoke test.

## Current state

### Generator manifest (as shipped by plan 031)

`examples/create-res-project/manifest.yaml`:
```yaml
name: create-res-project
classification: generator
description: Scaffold a ReScript project with a generic Rolldown bundler config matching the repository standard.
hooks:
  pre_generate: scripts/read-package-name.mjs
```

Missing: `post_generate` declaration.

### Pre-hook script (as shipped by plan 031)

`examples/create-res-project/scripts/read-package-name.mjs` reads
`package.json` from CWD (= outputDir), validates `name` is non-empty, and
prints `{"packageName":"<name>"}` on stdout. Exit non-zero on missing/invalid.

### Post-hook does NOT exist yet

`examples/create-res-project/scripts/setup-rescript.mjs` is the file to create.

### Discovery load-guard does NOT exist

`Discovery._loadManifest` (src/infrastructure/discovery/Discovery.res:64) parses
and validates the manifest but does NOT check that declared hook files exist on
disk. A manifest pointing to `scripts/nonexistent.mjs` loads successfully and
fails only at execution time (ENOENT). Spec scenario `generator-manifest-hooks#7`
requires a load-time ERROR.

### Repository dependency versions (for pinning)

From `package.json`:
```json
{
  "dependencies": {
    "@rescript/runtime": "^12.3.0",
    "rescript": "^12.3.0"
  },
  "devDependencies": {
    "rolldown": "^1.2.3",
    "rollup-plugin-esbuild": "^6.2.1"
  },
  "engines": { "node": ">=22.0.0" }
}
```

### Relevant test files

- `test/Manifest_test.res` — manifest parse/validate tests (9 hook tests from plan 031).
- `test/Discovery_test.res` — generator discovery tests (319 lines).
- `test/HookSecurity_test.res` — scriptRoot containment tests (2 from plan 031).
- `test/EngineIntegration_test.res` — integration harness (if it exists; verify #3056 referenced it).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Build ReScript | `pnpm res:build` | exit 0, zero new warnings |
| Run tests | `pnpm res:test` | all pass (3 pre-existing failures unchanged) |
| Run one test file | `pnpm res:test -- test/Discovery_test.res.mjs` | that suite passes |
| Full build | `pnpm build` | exit 0 |

> If `pnpm res:build` fails with `ERR_PNPM_MINIMUM_RELEASE_AGE_VIOLATION`,
> use `node_modules/.bin/rescript build` directly (environmental issue noted in verify #3056).

## Scope

**In scope**:
- `examples/create-res-project/scripts/setup-rescript.mjs` — **Create**
- `examples/create-res-project/manifest.yaml` — **Modify** (add `post_generate`)
- `src/infrastructure/discovery/Discovery.res` — **Modify** (add hook-file-existence load-guard)
- `test/Discovery_test.res` — **Modify** (add hook-path discovery test + load-guard test)
- `test/EngineIntegration_test.res` — **Modify** (add end-to-end smoke test, if harness exists)
- Engram design #3052 — **Update** (nested-switch syntax correction)

**Out of scope**:
- Any change to plan 030's bridge (`HookContext.res`, `Hooks.res` return type).
- Auto-installing dependencies (`pnpm add` / `npm install` from inside the hook).
- Any runtime source change beyond the Discovery load-guard.
- README for the generator (optional follow-up).

## Git workflow

- Branch: `plan/032-post-hook-and-followups` (or continue on current tree if user prefers).
- Commit per step; conventional commits.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Create `setup-rescript.mjs` post-hook script

File: `examples/create-res-project/scripts/setup-rescript.mjs`

The script:
1. Reads `package.json` from CWD (= outputDir, set by EngineOrchestrator).
2. Keeps `originalContent` in memory for in-script rollback.
3. Parses JSON; if parse fails → write stderr, exit 1.
4. Mutates the parsed object:
   - `dependencies`: add `"rescript": "^12.3.0"`, `"@rescript/runtime": "^12.3.0"` (merge; do not overwrite existing higher versions).
   - `devDependencies`: add `"rolldown": "^1.2.3"`, `"rollup-plugin-esbuild": "^6.2.1"` (same merge rule).
   - `scripts`: add `"res:build": "rescript"`, `"res:dev": "rescript watch"`, `"res:clean": "rescript clean"`, `"bundle": "rolldown -c"`, `"start": "node dist/main.mjs"`.
   - `engines`: set `"node": ">=22.0.0"` (overwrite if lower; keep if higher).
   - `main`: set `"dist/main.mjs"` only if absent (skip-if-present; matches `bin` rule).
   - `bin`: set `{ [pkg.name]: "dist/main.mjs" }` (merge; do not remove existing bin entries).
5. Serializes to JSON with 2-space indent + trailing newline.
6. Writes atomically: `fs.writeFileSync('package.json.tmp', json)` then `fs.renameSync('package.json.tmp', 'package.json')`.
7. If ANY step throws → restore `originalContent` via `fs.writeFileSync('package.json', originalContent)`, write stderr diagnostic, exit 1.
8. On success → write nothing to stdout (post-hook stdout is discarded), exit 0.

**Merge rules** (important):
- For `dependencies`/`devDependencies`: if the key already exists with a version, keep the existing version (user may have pinned differently). Only add if absent.
- For `scripts`: if the key already exists, keep the existing value. Only add if absent.
- For `engines.node`: set to `">=22.0.0"` only if the current value is lower or absent.
- For `main`: set only if absent (skip-if-present; user-pinned entry points win).
- For `bin`: merge; do not remove existing bin entries.

**Verify**:
```bash
cd /tmp && mkdir -p test-032 && cd test-032 && \
  echo '{"name":"my-app"}' > package.json && \
  node /home/metalbolicx/Documents/blueprint/examples/create-res-project/scripts/setup-rescript.mjs && \
  cat package.json
```
Expected: JSON with dependencies, devDependencies, scripts, engines, main, bin all present; `name` unchanged.

### Step 2: Update manifest to declare the post-hook

File: `examples/create-res-project/manifest.yaml`

```yaml
name: create-res-project
classification: generator
description: Scaffold a ReScript project with a generic Rolldown bundler config matching the repository standard.
hooks:
  pre_generate: scripts/read-package-name.mjs
  post_generate: scripts/setup-rescript.mjs
```

**Verify**: `pnpm res:build && pnpm res:test -- test/Discovery_test.res.mjs` → exit 0.

### Step 3: Add hook-file-existence load-guard in Discovery

File: `src/infrastructure/discovery/Discovery.res`, function `_loadManifest` (~line 64).

After parsing the manifest, if `manifest.hooks` is present:
```rescript
// Validate declared hook files exist relative to the generator directory
let hookCheck = switch manifest.hooks {
| None => Ok(())
| Some(h) =>
  switch h.preGenerate {
  | None => Ok(())
  | Some(path) =>
    let resolved = pathAdapter.resolve(generatorDir, path)
    switch await fs.fileExists(resolved) {
    | true => Ok(())
     | false => Error("Hook script not found: " ++ resolved)
    }
  }
}
// Repeat for postGenerate; short-circuit on first error.
```

Return the error from `_loadManifest` so Discovery surfaces it at load time
(before any generation begins).

**Verify**: `pnpm res:build && pnpm res:test -- test/Discovery_test.res.mjs` → exit 0 (existing tests still pass; new test added in step 4).

### Step 4: Add tests for discovery hook-path exposure + load-guard

File: `test/Discovery_test.res`

Two new tests:

1. **"discover: create-res-project generator carries both hook paths"** —
   discover `examples/create-res-project/`, assert `generator.manifest.hooks.preGenerate == Some("scripts/read-package-name.mjs")` and `generator.manifest.hooks.postGenerate == Some("scripts/setup-rescript.mjs")`.

2. **"discover: manifest with nonexistent hook file returns error"** —
   create a temp generator directory with a manifest pointing to
   `scripts/nonexistent.mjs`, attempt discovery, assert `Error` containing
   "Hook script not found".

**Verify**: `pnpm res:build && pnpm res:test -- test/Discovery_test.res.mjs` → all pass including 2 new.

### Step 5: Add end-to-end smoke test (if harness exists)

File: `test/EngineIntegration_test.res` (if it exists; otherwise skip and note as follow-up).

Test: "generate create-res-project: produces runnable project structure":
1. Create temp directory with `{"name":"smoke-app"}` as `package.json`.
2. Invoke the generator programmatically (or via test harness).
3. Assert:
   - `src/Main.res` exists and contains `"Hello, smoke-app!"`.
   - `rescript.json` exists and contains `"name": "smoke-app"`.
   - `rolldown.config.mjs` exists and is generic (no `VanRs`/`vanrs`).
   - `package.json` now contains `dependencies.rescript`, `scripts.res:build`, `engines.node`, `main`, `bin.smoke-app`.

If no integration harness exists, note as a follow-up and skip this step.

**Verify**: `pnpm res:build && pnpm res:test -- test/EngineIntegration_test.res.mjs` → pass (or skipped if no harness).

### Step 6: Update design #3052 for nested-switch syntax reality

Update Engram observation #3052 (`sdd/create-res-project/design`) to add a
"Syntax Addendum" section:

> **ReScript optional-field pattern matching**: The design's pseudo-code used
> `Some({hooks: Some({preGenerate: Some(s)})})` nested-record-pattern syntax.
> ReScript `?: T` optional record fields produce `option<T>` and require
> explicit `switch` at each level:
> ```rescript
> switch m.hooks {
> | Some(gh) => switch gh.preGenerate {
>   | Some(s) => ...
>   | None => ...
>   }
> | None => ...
> }
> ```
> The implementation in `EngineOrchestrator.res` uses this form. The design's
> nested-pattern pseudo-code was conceptual; this addendum documents the
> actual ReScript syntax.

Use `mem_update(id: 3052, content: "<existing content>\n\n## Syntax Addendum\n\n...")`.

**Verify**: `mem_get_observation(3052)` → addendum present.

### Step 7: Final build + test

```bash
pnpm res:build && pnpm res:test
```

Expected: exit 0; zero new warnings; all tests pass (3 pre-existing failures unchanged).

## Test plan

New tests to write:

**`test/Discovery_test.res`** — 2 new tests:
- Discovery surfaces both hook paths for `examples/create-res-project/`.
- Manifest with nonexistent hook file → Error at load time.

**`test/EngineIntegration_test.res`** — 1 new test (if harness exists):
- End-to-end generation produces correct files + package.json mutation.

**Manual smoke** — always run:
```bash
cd /tmp && rm -rf test-032 && mkdir test-032 && cd test-032 && \
  echo '{"name":"my-app"}' > package.json && \
  node /home/metalbolicx/Documents/blueprint/examples/create-res-project/scripts/setup-rescript.mjs && \
  cat package.json && \
  echo "---FAIL TEST---" && \
  rm package.json && \
  node /home/metalbolicx/Documents/blueprint/examples/create-res-project/scripts/setup-rescript.mjs; echo "exit=$?"
```
Expected: first run produces full package.json; second run exits non-zero with clear stderr (no package.json).

## Done criteria

ALL must hold:

- [ ] `pnpm res:build` exits 0; zero new warnings on touched files.
- [ ] `pnpm res:test` exits 0 (or 3 pre-existing failures only); new tests pass.
- [ ] `setup-rescript.mjs` mutates `package.json` with correct deps/scripts/engines/bin/main.
- [ ] `setup-rescript.mjs` restores original `package.json` on failure (in-script rollback).
- [ ] `setup-rescript.mjs` does NOT run `pnpm add`, `npm install`, or any package manager.
- [ ] `setup-rescript.mjs` does NOT print to stdout (post-hook stdout is discarded).
- [ ] Manifest declares `post_generate: scripts/setup-rescript.mjs`.
- [ ] Discovery load-guard rejects manifests with nonexistent hook files.
- [ ] Design #3052 addendum persisted to Engram.
- [ ] No `%raw`, no `Obj.magic`, no `Js.Json.parseExn` in any new code path.
- [ ] `ArchitectureGuard_test` passes.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report (do not improvise) if:

- The code at `Discovery.res:_loadManifest` does not match the described signature (drifted since plan 031).
- `test/EngineIntegration_test.res` does not exist and creating an integration harness would exceed the step's scope.
- The atomic-write approach (`writeFileSync` + `renameSync`) fails on the target platform (Windows).
- A step's verification fails twice after a reasonable fix attempt.
- `ArchitectureGuard_test` fails (CRITICAL — same lesson as plans 030/031).

## Maintenance notes

- **Future post-hook extensions**: if the scaffolded project later needs additional `package.json` mutations (e.g., tsconfig, eslint config), extend `setup-rescript.mjs` rather than adding another post-hook. One script = one atomic mutation boundary.
- **Version bumps**: when the repository upgrades ReScript or Rolldown, update the pinned versions in `setup-rescript.mjs` to match. The versions are in a single `const deps = { ... }` block at the top of the script for easy maintenance.
- **Auto-install decision**: if a future plan adds auto-install (Option A), it MUST handle lockfile rollback — either by extending Phase2's backup set to include `pnpm-lock.yaml`, or by running install in a separate post-generation step outside the transactional pipeline.
- **Reviewers**: scrutinize (1) the merge rules (add-if-absent, not overwrite), (2) the in-script backup mechanism, (3) that no stdout is printed, (4) that the load-guard error message is actionable.
