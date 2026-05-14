# Skill Registry — fluxo

## Project Context

- **Project**: fluxo
- **Type**: Go + ReScript template/code generator (hygen-inspired)
- **Location**: /home/metalbolicx/Documents/fluxo
- **Artifact Store**: engram
- **strict_tdd**: true (Go test runner detected — 93 tests across 10 packages)

## Detected Stack

| Component | Value |
|-----------|-------|
| Primary Language | Go 1.21 |
| Secondary Language | ReScript 12.x (ESM, compiles to .res.mjs) |
| YAML parsing | gopkg.in/yaml.v3 |
| Template engine | Go text/template + FuncMaps |
| Go test runner | `go test` — 93 tests passing |
| ReScript test runner | `retest` via rescript-test |
| Bundler | Rolldown v1 |
| Package Manager | pnpm |
| Module system | ESM (type: module) |
| Formatter | gofmt (no golangci-lint yet) |

## Architecture

- `cmd/fluxo/main.go` — CLI entry point
- `internal/` — Engine, phases (phase0/1/2), discovery, conflicts, hooks, manifest, templates
- `testdata/integration/` — Integration test fixtures
- `src/` — ReScript source
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
| go-testing | Go tests, go test coverage, golden files |
| subagent-driven-development | Executing implementation plans with independent tasks |
| test-driven-development | Before writing any feature or bugfix code |
| executing-plans | Written implementation plan to execute in separate session |
| work-unit-commits | Commit splitting, chained PRs, keeping tests with code |

## Testing Commands

- Go tests: `rtk go test ./... -v --count=1`
- ReScript build: `rtk pnpm res:build`
- ReScript tests: `rtk pnpm res:test`
- Bundle: `rtk pnpm bundle`

## Notes

- Package.json "name": "blueprint" but repo is "fluxo" — naming inconsistency
- openspec/changes/rescript-migration/tasks.md exists (pre-existing change artifact)
- Strict TDD auto-enabled because Go test infrastructure exists