# Plan 001: Publish the bundled CLI to npm with idempotent onboarding init

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat f5b5a29..HEAD -- package.json .npmignore src/interfaces/cli/commands/Init.res src/interfaces/cli/commands/InitGlobal.res src/interfaces/cli/Utils.res src/interfaces/cli/Help.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: dx | tech-debt
- **Planned at**: commit `f5b5a29`, 2026-08-12

## Why this matters

`package.json` maps `bin.blueprint` and `main` to `dist/main.mjs`, but `.npmignore:96`
excludes `dist`, so `npm publish` would ship a CLI with no executable. Separately, a
first-run user who runs `blueprint init` gets only a config file — nothing to actually
generate — so the first `blueprint generate` always fails with "generator not found".

This plan makes the published package real (only `dist` + docs ship) and turns `init`
into a true onboarding command that scaffolds a runnable hello-world example, locally
or globally, idempotently (re-runs are safe no-ops, never destructive). No CI/GitHub
Actions are added — release is a documented local sequence.

## Current state

ReScript 12 CLI, ESM, in-source compilation (`.res` → `.res.mjs`). Build is two-step:
`rescript` compiles, then `rolldown -c` bundles `src/interfaces/cli/Main.res.mjs` →
`dist/main.mjs` with a `#!/usr/bin/env node` banner; `ejs`, `yaml`, `@rescript/runtime`
stay external (runtime deps). Tests run via `retest ./test/*.res.mjs`.

The facts the executor needs:

- `package.json:9-19` — `scripts`. No `files` field anywhere in the file; no
  `prepublishOnly`. `main: "dist/main.mjs"` at line 40; `bin` at lines 6-8.
- `.npmignore:96` — bare `dist` line (under a "Nuxt.js" comment block) excludes the
  bundle. `.npmignore:170-171` — `*.config.*` excludes configs (harmless for packaging,
  but the executor should be aware).
- `src/interfaces/cli/commands/Init.res:1-15` — `runInit` writes `.blueprint.yaml` in
  `cwd`; on existing config it does `Console.error(...)` + `deps.process.exit(1)` (lines
  6-9). Config content is an inline string at line 11.
- `src/interfaces/cli/commands/InitGlobal.res:1-24` — `runInitGlobal` writes
  `~/.config/blueprint/config.yaml` (creates the dir with `mkdir ~options={recursive:
  true}` at line 16). Same `exit(1)` on existing (lines 8-11). Config content inline at
  line 20, includes `templates: []`.
- `src/interfaces/cli/Commands.res:11,34` — `runInitGlobal`/`runInit` are thin aliases
  to the command modules; called from `src/interfaces/cli/Router.res:82,87`.
- `src/interfaces/cli/Router.res:80-89` — `routeInit`: if args include `--global` →
  `runInitGlobal`, else `runInit`. Flag parsing helper `parseCommandFlag` at lines 18-22
  (checks `--<name>` and `-<first char>`).
- `src/interfaces/cli/Utils.res:1-4` — `globalTemplateRegistryRoot` returns
  `~/.config/blueprint/templates`. **Defined but NOT used by discovery.**
- `src/interfaces/cli/Utils.res:11-27` — `buildGenerateSearchPaths`: returns
  `projectPaths ++ registryDirs ++ globalTemplates`. `projectPaths` from
  `Generate.res:30` are `["_templates", "templates", "generators"]` (relative to cwd).
  The global templates root is NOT appended, so a global hello-world is invisible to
  `generate` today.
- `src/interfaces/cli/Generate.res:30-37` — search-path construction + `Discovery.discover`.
- `src/interfaces/cli/Help.res:21-22,66-78` — usage listing + `init [--global]` help block.
- Ports API surface (`src/domain/ports/Ports.res`):
  - `fileSystem.writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit>`
  - `fileSystem.mkdir: (string, ~options: mkdirOptions=?) => promise<string>` (returns the path)
  - `fileSystem.fileExists: string => promise<bool>`
  - `mkdirOptions = {recursive: bool}`; `writeFileOptions = {encoding: string}`
  - `process.cwd: unit => string`; `process.homedir: unit => string`
  - `path.join: (string, string) => string`

### Repo conventions to honor

- **Idempotency model**: this plan INTRODUCES idempotent no-op behavior for `init`
  (current code hard-fails with `exit(1)`). The new contract is "create only what's
  missing; never overwrite; re-runs exit 0 with an informational message". This is a
  deliberate behavior change approved by the user — do NOT preserve the `exit(1)`.
- **Inline string assets**: config files are embedded as string constants in the
  command module (see `Init.res:11`, `InitGlobal.res:20`). The hello-world example
  template MUST follow the same pattern (embedded string), so the npm package needs no
  extra asset files beyond `dist`.
- **Error handling**: uses `Console.error` / `Console.log` / `deps.process.exit(n)`.
  Match it. No Result types for the user-facing init path.
- **No comments** in the source unless asked; match existing file style.
- **Test pattern**: model new tests EXACTLY on `test/Commands_test.res`:
  - `open TestHelpers` at top.
  - Build `Ports.deps` via a `makeDeps(~cwd, ~exitCodes, ...)` factory using real
    `NodeJsFileSystem.make()` for `fs`, a `process` whose `exit` pushes to an
    `exitCodes: ref<array<int>>`, `homedir: () => "/tmp/test-home"`.
  - Use a real temp dir: `let tmpDir = NodeJs.Os.makeStagingDir()`.
  - Use `testAsync("...", resolve => { ... ->Promise.then(_ => { assertions;
    resolve(unit) }) })`.
  - Assertions: `assert_eq`, `assert_false`, etc. from `TestHelpers`.
- **Template file format** (Hygen-compatible EJS with YAML frontmatter): the example
  is a single `.ejs.t` file whose frontmatter `to:` names the output path and whose
  body is EJS.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile | `pnpm res:build` | exit 0 |
| Full build (compile + bundle) | `pnpm build` | exit 0, `dist/main.mjs` exists |
| Run all tests | `pnpm res:test` | all pass |
| Coverage gate | `pnpm res:test:coverage:check` | exit 0 (lines≥50 fn≥50 branches≥40) |
| Inspect npm tarball | `npm pack --dry-run` | only `dist/`, `README.md`, `LICENSE`, `package.json` |

There are NO `lint`/`typecheck` npm scripts — `pnpm res:build` is the type check.

## Scope

**In scope** (the only files you should modify):
- `package.json` — `files`, `prepublishOnly`.
- `.npmignore` — remove the `dist` exclusion.
- `src/interfaces/cli/commands/Init.res` — idempotent config + scaffold hello-world.
- `src/interfaces/cli/commands/InitGlobal.res` — idempotent config + global templates dir + hello-world.
- `src/interfaces/cli/Utils.res` — include global templates root in search paths.
- `src/interfaces/cli/Help.res` — update init help to mention templates.
- `test/Init_test.res` — create (new).
- `test/InitGlobal_test.res` — create (new).
- `README.md` — install / init / first-generate / local release docs.

**Out of scope** (do NOT touch):
- Any GitHub Actions / `.github/workflows/` — explicitly excluded by the user.
- `src/interfaces/cli/commands/Generate.res` discovery call (it already consumes
  `buildGenerateSearchPaths`; the change lives in `Utils.res`).
- Bundling templates into `dist` or shipping `_templates/` from this repo in the npm
  package — templates are user-owned; the repo's `_templates/` are examples.
- `rolldown.config.mjs` externals — unchanged.
- `--force` semantics — NOT added in this plan (idempotent no-op only).

## Git workflow

- Branch: `feat/npm-bundle-idempotent-init`
- Conventional commits, one per work unit below (Step = commit). Recent repo style
  example: `feat(...)`, `fix(...)`, `test(...)`, `docs(...)` — check `git log --oneline -8`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Define publishable package contents

Commit message: `build(npm): publish only dist and docs`

1. In `package.json`, add a `files` allowlist (place it near `main`, e.g. after line 40):
   ```json
   "files": ["dist", "README.md", "LICENSE"]
   ```
2. In `package.json` `scripts` (lines 9-19), add:
   ```json
   "prepublishOnly": "pnpm build"
   ```
3. In `.npmignore`, delete the bare `dist` line at line 96 (the `.nuxt`/`dist` block
   under the Nuxt comment). Leave the rest of the file intact.

**Verify**:
- `pnpm build` → exit 0, `dist/main.mjs` exists.
- `npm pack --dry-run` → the file list contains `dist/main.mjs`, `README.md`,
  `package.json`, `LICENSE`; it does NOT contain `src/`, `test/`, `_templates/`,
  `examples/`, or `*.res`. (Note: with a `files` allowlist, npm always also includes
  `package.json`/`README`/`LICENSE`.)

### Step 2: Make `init` idempotent and scaffold a local hello-world

Commit message: `feat(init): scaffold runnable hello-world template idempotently`

Rewrite `src/interfaces/cli/commands/Init.res` so `runInit`:
1. Computes `cwd` and `configPath` as today.
2. **Config**: if `.blueprint.yaml` exists → `Console.log("...already exists, skipping")`
   (NOT an error) and continue; else write it (keep the existing content string).
3. **Templates dir + example**: target dir = `path.join(cwd, "_templates", "hello-world",
   "new")`. `mkdir ~options={recursive: true}` (ignore the returned path). Example file
   = `hello.ejs.t`. If `fileExists(exampleFile)` is already true → skip with an
   informational `Console.log`; else write the embedded example string below.
4. End with `Console.log` summarizing what was created/skipped. Always exit 0 (do not
   call `deps.process.exit` at all on the success path).

Embedded example constant (frontmatter `to:` writes into the user's project; `name` is
the standard generator name attribute):
```
---
to: hello-<%= name %>.md
---
# Hello, <%= name %>!

Generated by Blueprint. Edit _templates/hello-world/new/hello.ejs.t to customize.
```

Also update `src/interfaces/cli/Help.res:66-78` so the `init` help block states it
scaffolds a `.blueprint.yaml` **and** a starter `_templates/hello-world` example, and
that re-runs are safe no-ops.

**Verify**: `pnpm res:build` → exit 0.

### Step 3: Make `init --global` idempotent and scaffold a global hello-world

Commit message: `feat(init): scaffold global hello-world template idempotently`

Rewrite `src/interfaces/cli/commands/InitGlobal.res` so `runInitGlobal`:
1. Computes the global config dir/path as today (`~/.config/blueprint/config.yaml`).
2. **Config**: same idempotent skip-or-create pattern as Step 2 (exit(1) → skip+log).
3. **Global templates dir + example**: use the canonical root
   `Utils.globalTemplateRegistryRoot(~deps)` (= `~/.config/blueprint/templates`).
   `mkdir ~options={recursive: true}` on `path.join(root, "hello-world", "new")`, then
   write the SAME embedded `hello.ejs.t` example (idempotent skip if it exists).
4. End with a `Console.log` summary. Always exit 0 on the success path.

Reuse the exact same embedded example string as Step 2 (define it once locally in each
module, matching how each command currently inlines its own config string at
`Init.res:11` / `InitGlobal.res:20` — do NOT introduce a shared module).

**Verify**: `pnpm res:build` → exit 0.

### Step 4: Make the global templates root discoverable

Commit message: `feat(discovery): include global templates root by default`

In `src/interfaces/cli/Utils.res`, change `buildGenerateSearchPaths` (lines 11-27) so the
final array also appends the global templates root when it is not already present:
```rescript
let globalRoot = globalTemplateRegistryRoot(~deps)
projectPaths->Array.concat(registryPaths)->Array.concat(globalTemplates)->Array.concat([globalRoot])
```
(Dedup is already handled for `registryPaths`; add the same `Array.includes` guard for
`globalRoot` so it never duplicates a project `templates` entry.)

This makes the global hello-world from Step 3 runnable via `blueprint generate hello-world X`.

**Verify**:
- `pnpm res:build` → exit 0.
- `pnpm res:test` → all pass (watch `test/Utils_test.res` and
  `test/TemplateRegistry_test.res` — they assert on `buildGenerateSearchPaths` output; if
  any now-expecting-3-paths assertion breaks, the test expectation must be updated to
  include the new global root, NOT the production code reverted).

### Step 5: Tests for idempotent init (local + global)

Commit message: `test(init): cover idempotent scaffolding and non-destructive re-runs`

Create `test/Init_test.res` and `test/InitGlobal_test.res`, modeling `test/Commands_test.res`:

- `makeDeps(~cwd, ~exitCodes, ...)` with real `NodeJsFileSystem.make()`, `homedir` pointing
  at a temp dir, `exit` pushing to a ref.
- `test/Init_test.res` cases:
  1. Fresh run in empty temp cwd → `.blueprint.yaml` AND
     `_templates/hello-world/new/hello.ejs.t` both exist; `exitCodes` is empty (exit 0).
  2. Second run (re-run) → no crash, `exitCodes` empty, files unchanged (assert content
     equals what was written on run 1), console mentions "skipping"/"already".
  3. Pre-existing user generator in `_templates/usergen/` survives untouched (assert the
     user file's content is byte-identical after `runInit`).
- `test/InitGlobal_test.res` cases (point `homedir` at a temp dir):
  1. Fresh run → `config.yaml` and `<templatesRoot>/hello-world/new/hello.ejs.t` exist.
  2. Re-run → idempotent no-op, exit 0, files unchanged.
  3. Non-destructive on a pre-existing global user generator.

**Verify**: `pnpm res:test` → all pass, including the new tests.

### Step 6: End-to-end + packed-install smoke coverage

Commit message: `test(npm): pack, install, and run scaffolded generator`

Add to `test/SmokeIntegration_test.res` (existing) OR a new `test/NpmPack_test.res`:
a test that (a) builds, (b) confirms `blueprint init` in a temp dir creates the
hello-world example, then (c) runs the generation path so the scaffolded example
produces `hello-<name>.md`. If a true `npm pack` + `npm i` flow is impractical inside
`retest`, instead assert the scaffolded example renders via the existing Engine path
(this satisfies the same correctness contract without network/registry access).

Keep coverage above the gate (see Done criteria).

**Verify**: `pnpm res:test` → all pass; `pnpm res:test:coverage:check` → exit 0.

### Step 7: Document install, init, and the local release sequence

Commit message: `docs: document install, init onboarding, and local npm release`

Update `README.md`:
- Install: `npm install -g blueprint` and `npx blueprint ...`.
- Onboarding: `blueprint init` (project) / `blueprint init --global` (global), then
  `blueprint generate hello-world <name>`. Note re-runs are safe.
- Local release sequence (no CI): clean worktree → `pnpm build` → `pnpm res:test` →
  `pnpm res:test:coverage:check` → `npm pack --dry-run` (inspect) → `npm publish
  --access public` → tag `v<version>` and push tags only after publish succeeds.

**Verify**: `pnpm build` → exit 0 (README is not compiled, but ensure no broken doc
references).

## Test plan

- New `test/Init_test.res` and `test/InitGlobal_test.res`: idempotency (fresh, re-run,
  partial state), non-destruction of user generators. Model on `test/Commands_test.res`.
- Update `test/Utils_test.res` / `test/TemplateRegistry_test.res` expectations if the
  global-root addition changes their asserted path counts (update expectations, not
  production logic).
- End-to-end smoke: scaffolded hello-world actually generates a file.
- Full suite: `pnpm res:test`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm build` exits 0 and `dist/main.mjs` exists
- [ ] `pnpm res:test` exits 0; new `Init_test`/`InitGlobal_test` exist and pass
- [ ] `pnpm res:test:coverage:check` exits 0 (lines≥50 / fn≥50 / branches≥40)
- [ ] `npm pack --dry-run` lists `dist/main.mjs` and does NOT list `src/`, `test/`,
      `_templates/`, `examples/`, or `*.res`
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `grep -n "dist" .npmignore` returns no bare `dist` line at the old location
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- `Init.res` / `InitGlobal.res` / `Utils.res` / `package.json` / `.npmignore` no longer
  match the "Current state" excerpts above (drift since `f5b5a29`).
- `npm pack --dry-run` still excludes `dist` after removing the `.npmignore` line AND
  adding the `files` field (npm precedence is unexpected — report rather than guess).
- A `buildGenerateSearchPaths` test fails because of the global-root addition and the
  "update expectation, don't revert" guidance is ambiguous.
- `fileExists`/`mkdir` on the Ports interface do not match the signatures inlined above.
- The scaffolded hello-world's `to: hello-<%= name %>.md` does not render through the
  Engine (the `name` attribute plumbing differs from the assumption).
