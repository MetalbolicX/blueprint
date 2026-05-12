# Skill Registry — fluxo

## Project Context

- **Project**: fluxo
- **Type**: Greenfield Go-based code/template generator
- **Location**: /home/metalbolicx/Documents/fluxo
- **Artifact Store**: engram
- **strict_tdd**: false (no test runner yet)

## Detected Stack

| Component | Value |
|-----------|-------|
| Language | Go only |
| YAML parsing | gopkg.in/yaml.v3 |
| Template engine | Go text/template + FuncMaps |
| Storage | File-system based (manifest.yaml) |
| Test runner | None yet (greenfield) |
| Linter | TBD |
| Formatter | gofmt |

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
| go-testing | Go tests, go test coverage, Bubbletea teatest, golden files |
| subagent-driven-development | Executing implementation plans with independent tasks |
| test-driven-development | Before writing any feature or bugfix code |
| executing-plans | Written implementation plan to execute in separate session |
| work-unit-commits | Commit splitting, chained PRs, keeping tests with code |

## Notes

- This is a greenfield project — no existing Go code or tests yet
- strict_tdd will be set to true once Go test infrastructure is established
- Handoff doc at `docs/fluxo-handoff-2026-05-11.md` defines the architecture baseline
