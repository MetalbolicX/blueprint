# Tasks: Fluxo ReScript Migration

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 3500-4000 (full migration) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | Phase-by-phase per SDD phase structure |
| Delivery strategy | ask-on-risk |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: High

User preference: Small incremental phases, not all at once.

### Suggested Work Units

| Unit | Goal | Notes |
|------|------|-------|
| 1 | Project setup + bindings | rescript.json, package.json, bindings layer |
| 2 | Core types + FuncMap + Frontmatter | Domain types, funcmaps, frontmatter parser |
| 3 | Manifest + Config + Discovery | Parsing and discovery |
| 4 | Phase0 + Phase1 | Prompt resolution, staging, rendering, injection |
| 5 | Phase2 + Hooks + ConflictResolver | Commit, rollback, hooks |
| 6 | Engine + CLI | Orchestrator and entry point |
| 7 | Testing | Unit, integration, e2e tests |

## Phase 1: Project Setup

- [x] 1.1 Create `rescript.json` with v12 config (esmodule, in-source, suffix: .mjs)
- [x] 1.2 Create `package.json` with bin entry `fluxo`, deps: `ejs`, `yaml`, `@rescript/runtime`
- [x] 1.3 Create `src/bindings/Ejs.res` — EJS render bindings with options type
- [x] 1.4 Create `src/bindings/Yaml.res` — yaml npm package bindings
- [x] 1.5 Create `src/bindings/ParseArgs.res` — node:util parseArgs bindings
- [x] 1.6 Create `src/bindings/Readline.res` — node:readline bindings for prompts
- [x] 1.7 Create `src/bindings/Fs.res` — node:fs/promises bindings
- [x] 1.8 Create `src/bindings/Path.res` — node:path bindings
- [x] 1.9 Create `src/bindings/ChildProcess.res` — node:child_process bindings
- [x] 1.10 Create `src/bindings/Os.res` — node:os bindings (tmpdir for staging)
- [x] 1.11 Create `_templates/component/new/manifest.yaml` — dogfooding template
- [x] 1.12 Create `_templates/component/new/index.tsx.ejs.t` — dogfooding template

## Phase 2: Core Types & Template System

- [ ] 2.1 Create `src/templates/Template.res` — directive variant types and template record
- [ ] 2.2 Create `src/templates/FuncMap.res` — pascalCase, camelCase, kebabCase, snakeCase, upper, lower, trim, title
- [ ] 2.3 Create `src/templates/Frontmatter.res` — parse YAML frontmatter from .ejs.t files
- [ ] 2.4 Create `src/templates/Renderer.res` — EJS rendering with funcmaps injected as `h.*`
- [ ] 2.5 Create `src/templates/Injection.res` — inject/after/before/prepend/append logic

## Phase 3: Manifest, Config & Discovery

- [ ] 3.1 Create `src/Manifest.res` — parse and validate manifest.yaml
- [ ] 3.2 Create `src/Config.res` — load and parse .fluxo.yaml hooks config
- [ ] 3.3 Create `src/Discovery.res` — traverse _templates/ directory, find generators

## Phase 4: Context & Prompt Resolution

- [ ] 4.1 Create `src/Context.res` — name variants, attributes, merge priority (CLI > prompts > defaults)
- [ ] 4.2 Create `src/PromptResolver.res` — interactive input/select/confirm via node:readline
- [ ] 4.3 Create `src/ConflictResolver.res` — bulk y/n/s/a conflict resolution

## Phase 5: Pipeline Phases

- [ ] 5.1 Create `src/phases/Phase0.res` — prompt collection + conflict detection
- [ ] 5.2 Create `src/phases/Phase1.res` — staging, template rendering, injection dispatch, shell queue
- [ ] 5.3 Create `src/phases/Phase2.res` — atomic commit from staging to output, rollback on failure
- [ ] 5.4 Create `src/Hooks.res` — pre/post generate hook execution

## Phase 6: Engine & CLI

- [ ] 6.1 Create `src/Engine.res` — 3-phase pipeline orchestrator
- [ ] 6.2 Create `src/Cli.res` — CLI entry point using parseArgs (init + generate commands)

## Phase 7: Testing

- [ ] 7.1 Create `test/FuncMap_test.res` — all case conversions, edge cases
- [ ] 7.2 Create `test/Frontmatter_test.res` — valid/invalid frontmatter parsing
- [ ] 7.3 Create `test/Manifest_test.res` — manifest parse and validation
- [ ] 7.4 Create `test/Context_test.res` — name variant generation, merge priority
- [ ] 7.5 Create `test/Template_test.res` — directive parsing
- [ ] 7.6 Create `test/Phase0_test.res` — prompt resolution
- [ ] 7.7 Create `test/Phase1_test.res` — staging and rendering
- [ ] 7.8 Create `test/Phase2_test.res` — commit and rollback
- [ ] 7.9 Create `test/Injection_test.res` — all injection modes
- [ ] 7.10 Create `test/ConflictResolver_test.res` — y/n/s/a resolution
- [ ] 7.11 Create `test/Engine_test.res` — full pipeline e2e