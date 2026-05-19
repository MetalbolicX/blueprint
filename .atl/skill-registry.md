# Skill Registry — blueprint

## Project Context

- **Project**: blueprint
- **Type**: ReScript template/code generator (hygen-inspired)
- **Location**: /home/metalbolicx/Documents/blueprint
- **Artifact Store**: engram

## Detected Stack

| Component | Value |
|-----------|-------|
| Language | ReScript 12.x (ESM, compiles to .res.mjs) |
| Template engine | EJS |
| Test runner | `retest` via rescript-test |
| Bundler | Rolldown v1 |
| Package Manager | pnpm |
| Module system | ESM (type: module) |

## Architecture

- `src/interfaces/cli/` — CLI entry point
- `src/application/engine/` — Pipeline orchestrator
- `src/application/pipeline/` — Phases (phase0/1/2)
- `src/infrastructure/discovery/` — Template discovery
- `src/infrastructure/rendering/` — EJS rendering
- `src/infrastructure/prompts/` — Interactive prompt resolution
- `src/infrastructure/bindings/` — Node.js/third-party bindings
- `src/domain/context/` — Context building, name variants
- `_templates/` — Hygen-compatible generator templates
- `test/res/` — ReScript tests (.res.mjs suffix)

## SDD Phases Supported

| Phase | Status |
|-------|--------|
| sdd-init | ✅ Initialized |
| sdd-explore | Available |
| sdd-propose | Available |
| sdd-spec | Available |
| sdd-design | Available |
| sdd-tasks | Available |
| sdd-apply | Available |
| sdd-verify | Available |
| sdd-archive | Available |

## Relevant Skills

| Skill | Trigger |
|-------|---------|
| subagent-driven-development | Executing implementation plans with independent tasks |
| test-driven-development | Before writing any feature or bugfix code |
| executing-plans | Written implementation plan to execute in separate session |
| work-unit-commits | Commit splitting, chained PRs, keeping tests with code |

## Testing Commands

- ReScript build: `pnpm res:build`
- ReScript tests: `pnpm res:test`
- Bundle: `pnpm bundle`