# Session Handoff

## Next Session Focus

Implement the Go-based template generator from the finalized architecture plan. The core engine (manifest parsing, discovery, phase 0/1/2 execution, frontmatter parsing, rendering with FuncMaps) is ready to be built following the TDD-style plan established in this session.

## Context & Summary

We have completed an architectural deep-dive and plan review for a new Go-based code/template generator to replace `hygen`. The session followed the `conceptual-grill` skill to iteratively challenge and validate decisions, ensuring the resulting architecture solves `hygen`'s pain points.

### Key Decisions Made

1.  **Language:** Go only (standard library preferred, `gopkg.in/yaml.v3` for parsing).
2.  **Storage:** File-system based (nested folders) with `manifest.yaml` as the source of truth for metadata, classification, and declarative prompts.
3.  **Layout:** Strict separation of concerns per template: `manifest.yaml`, `hooks/`, `files/`.
4.  **Execution:** Three-phase transactional process:
    - Phase 0: Declarative Prompt gathering and Collision Detection (upfront, bulk resolution).
    - Phase 1: Sandbox Staging, Render (Go `text/template` + FuncMaps), and Regex Injection into sandbox copies of existing files.
    - Phase 2: Atomic Commit (OS temp dir) with rollback on failure.
5.  **Conflict Resolution:** `--force` flag + bulk interactive prompt (`[y]es to all, [n]o to all, [s]elect individually, [a]bort`), removing `hygen`'s sequential prompt fatigue.
6.  **Templating:** Go's standard `text/template` with custom `FuncMaps` for string manipulation (pascalCase, camelCase, kebabCase, etc.) to replace EJS.
7.  **Frontmatter:** Template files keep `hygen`-style frontmatter for file-specific rules (`to`, `inject`, `after`, `before`, `prepend`, `append`, `force`, `sh`).
8.  **Hook Lifecycle:** Support for `pre_generate` and `post_generate` hooks in `hooks/` directory, callable via `os/exec` (JS, Python, PowerShell, Bash, etc.).
9.  **Search:** Ephemeral index built from `manifest.yaml` files during discovery for fast classification and search.

### Pain Points Being Solved

- `hygen` lacks search/classification (solved by manifest + index).
- `hygen` lacks transactional execution (solved by sandbox two-phase commit).
- `hygen` only allows one shell command per file, fixed to bash (solved by multi-language hooks + lifecycle system).
- `hygen` lacks regex injection (solved by Phase 1 injection logic).

## External Artifacts

- **Implementation Plan (v2):** This session produced a TDD-style implementation plan with 5+ bite-sized tasks. The plan was drafted in the conversation but needs to be written to a file. (Next agent should create `docs/superpowers/plans/2026-05-11-go-based-template-generator.md`).
- **Memory Saves:** The following Engram memories were saved in this session and should be referenced:
  - `obs-03d80cf7677e9476`: "Architecture: Go-based Template Generator Baseline"
  - `obs-fc6573dc61621d25`: "Hygen Feature Review"
  - `obs-a4b6ccd0fa40bd81`: "Architecture: Hygen Feature Mapping Confirmed"

## Suggested Skills

- **subagent-driven-development:** For dispatching agents to implement the plan task-by-task.
- **executing-plans:** For inline implementation if preferred.
- **TDD (test-driven-development):** The plan is fully TDD-driven, starting with writing failing tests.
- **go-testing:** For Go-specific testing patterns if needed.
