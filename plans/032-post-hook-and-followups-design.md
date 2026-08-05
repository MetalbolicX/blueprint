# Design: Post-hook (setup-rescript.mjs) + Discovery load-guard + verify follow-ups

## Context recap

Plan 032 adds a mutate-only post-hook and fail-closed loading. It mutates pre-existing `package.json`; Phase2 rollback is unchanged.

## Technical Approach

Reuse Plan 030/lifecycle. Add one file-only Node ESM script and one Discovery guard.

## Architecture overview / Data Flow

```text
pre-hook (outputDir) -> HookContext -> templates -> Phase2 commit
                                                    -> post-hook -> exit
manifest.yaml -> parse/validate -> resolve(generatorDir, hookPath)
               -> fs.fileExists -> Ok | Error(absolute path; fail closed)
```

## Component design

### `examples/create-res-project/scripts/setup-rescript.mjs`

Import only `node:fs` and `node:path`. Define:

```js
const TOOLCHAIN_DEPS = {rescript: "^12.3.0", "@rescript/runtime": "^12.3.0"}
const TOOLCHAIN_DEV_DEPS = {rolldown: "^1.2.3", "rollup-plugin-esbuild": "^6.2.1"}
const SCRIPTS = {"res:build": "rescript", "res:dev": "rescript watch", "res:clean": "rescript clean", bundle: "rolldown -c", start: "node dist/main.mjs"}
const NODE_FLOOR = ">=22.0.0"
const MAIN_FIELD = "dist/main.mjs"
```

`main()` reads CWD `package.json`, saves `originalContent`, parses, then calls `mergeAddIfAbsent` for dependencies/devDependencies/scripts, `mergeFloorRaise` for `engines.node`, and `mergeBin`. Set `main` only when absent. Serialize with two-space indentation/newline; atomically run `fs.writeFileSync('package.json.tmp', json)` then `fs.renameSync('package.json.tmp', 'package.json')`. Any post-backup throw runs `fs.writeFileSync('package.json', originalContent)`, writes stderr, and exits 1. ENOENT, read EACCES, SyntaxError, and write EACCES/EROFS fail closed; pre-backup read failure has nothing to restore. Success is silent. No `child_process`/package manager.

### `examples/create-res-project/manifest.yaml`

Add `hooks.post_generate: scripts/setup-rescript.mjs`; describe a runnable ReScript project. Omit unsupported `version: 1`.

### `src/infrastructure/discovery/Discovery.res`

After `Manifest.validate`, check both paths with `pathAdapter.resolve(generatorDir, path)` and `fs.fileExists`, short-circuiting on a miss. Keep `result<option<Manifest.manifest>, string>` and return `Error("Hook script not found: " ++ resolved)`; no generator reaches `Engine.run`.

### Tests

`Discovery_test.res`: `discover: create-res-project generator carries both hook paths` asserts both `Some(...)`; `discover: manifest with nonexistent hook file returns error` asserts absolute path. `EngineIntegration_test.res`: `generate create-res-project: produces runnable project structure` uses `EngineOrchestrator` with `{"name":"smoke-app"}` and checks `src/Main.res` greeting, `rescript.json` name, generic `rolldown.config.mjs`, and package metadata.

## Interfaces / Contracts

`generatorHooks` remains `{preGenerate?: string, postGenerate?: string}`; `_loadManifest` remains `promise<result<option<Manifest.manifest>, string>>`; the hook has a `package.json` contract.

## Architecture Decisions

| # | Choice | Alternative | Rationale |
|---|---|---|---|
| 1 | Mutate-only | `pnpm add` | Package/lockfile state is outside Phase2’s committed set. |
| 2 | In-script backup + atomic write | Phase2 rollback | Preserves consistent bytes across interrupted writes. |
| 3 | Repo-matching caret ranges | Exact pins | Matches repo; users may lock later. |
| 4 | Add-if-absent | Overwrite pins | Respects user intent. |
| 5 | Skip-if-present `main`; merge `bin` | Always overwrite | Preserves user entry points and bin entries. |
| 6 | Load-time guard | Runtime check | Fails before generation. |
| 7 | Absolute error path | Relative path | Actionable and spec-compliant. Follow-on: plan Step 3 uses `resolved`, not declared `path`. |
| 8 | Silent stdout | Success message | Post-hook stdout is discarded; diagnostics use stderr. |

## File change matrix

| File | Action | Lines | Purpose |
|---|---|---:|---|
| `examples/create-res-project/scripts/setup-rescript.mjs` | CREATE | ~90 | Mutation. |
| `examples/create-res-project/manifest.yaml` | MODIFY | +2 | Hook/description. |
| `src/infrastructure/discovery/Discovery.res` | MODIFY | +15–25 | Load guard. |
| `test/Discovery_test.res` | MODIFY | +30–50 | Discovery tests. |
| `test/EngineIntegration_test.res` | MODIFY | +40–60 | Smoke test. |
| `sdd/create-res-project/design` (Engram #3052) | UPDATE | +200 bytes | Syntax addendum. |

180–220 lines; under 400.

## Testing Strategy

| Layer | Coverage | Approach |
|---|---|---|
| Unit | Merge rules/load guard | ReScript plus Node failure/pin cases. |
| Integration/E2E | Lifecycle/output | Harness; files, metadata, order, stdout, failure. |

## Verification plan

Run `pnpm res:build` (exit 0, no new warnings), `pnpm res:test` (new tests pass; three known failures only), and `pnpm res:test -- test/Discovery_test.res.mjs`. Manual smoke: temp dir, echo package.json, run script, cat output; then rm package.json, rerun, assert exit 1/stderr.

## Threat Matrix

| Boundary | Applicability | Safe/failure behavior | Planned RED test |
|---|---|---|---|
| Documentation-like paths | N/A — no classification change. | Existing classification remains. | None. |
| Git repository selection | N/A — no git selector. | No repository selection. | None. |
| Commit state | N/A — no VCS index/commit automation. | Post-hook failure leaves committed files as-is; receipt is deferred. | None. |
| Push state | N/A — no remote behavior. | No push/refspec changes. | None. |
| PR commands | N/A — no PR automation. | No PR command composition. | None. |

## Migration / Rollout

No migration.

## Risks & mitigations

- WARNING: main overwrite/lower pins are resolved by skip-if-present/add-if-absent.
- MEDIUM: post-hook failure leaves rendered files committed; script backup retained, receipt deferred.
- LOW: `renameSync` on Windows; target Linux.
- LOW: load-guard signature drift; verified live.

## Out of scope

No auto-install, Plan 030 bridge changes, runtime change beyond Discovery, generator README, or Phase2 rollback-receipt change.

## Open Questions

None; proposal and spec decisions are locked.
