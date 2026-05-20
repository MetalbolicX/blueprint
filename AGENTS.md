# Blueprint — Agent Guidance

## Build & Test

```bash
pnpm build           # rescript && rolldown -c  (compiler THEN bundler)
pnpm res:build       # ReScript compile only
pnpm res:dev         # ReScript watch mode
pnpm res:test        # retest ./test/*.res.mjs — single test runner
pnpm bundle          # rolldown -c (bundle only, assumes ReScript already compiled)
```

- **Build is two-step**: ReScript compiles `.res` → `.res.mjs` in-source, then Rolldown bundles `dist/main.mjs` from `src/interfaces/cli/Main.res.mjs`.
- **Run a focused test**: `pnpm res:test` runs ALL tests. To run a single test, add `--` or use `npx retest ./test/Some_test.res.mjs`.
- **No CI detected** — no `.github/` workflows.

## Architecture

- **Hexagonal/Clean**: `interfaces/` → `application/` → `domain/` + `infrastructure/`
- **3-phase pipeline**: Phase0 (prompt resolution + conflict detection), Phase1 (render to staging + shell), Phase2 (atomic commit to output + cleanup)
- **Transactional**: renders to `os.TempDir()` staging — on error, `Phase2.rollback(stagingDir)` removes it. No partial writes reach output.
- **Conflict resolution**: bulk y/n/s/a per file. Use `--force` to skip.

## Language & Tooling

- **Language**: ReScript 12.x, ESM (`"type": "module"`), in-source compilation (`.res.mjs` suffix)
- **No TypeScript** — `.ts` files are gitignored (npmignore includes `src/**/*.ts`)
- **LSP**: rescript-language-server configured in `.opencode/opencode.json`
- **ast-grep grammar**: rescript grammar installed at `.ast-grep/grammars/rescript.so` — use `ast_grep_search` with `lang: "rescript"`
- **Formatter**: no project-specific formatter detected (editorconfig only)

## Key Dependencies

- `ejs` — template rendering engine
- `yaml` — config/manifest parsing
- `@rescript/runtime` — ReScript runtime
- `rescript-test` (`retest`) — test runner (dev)

## Directory Map

| Path | Purpose |
|------|---------|
| `src/interfaces/cli/` | CLI entrypoint (`Main.res` → `dist/main.mjs`) |
| `src/application/engine/` | Pipeline orchestrator |
| `src/application/pipeline/` | 3-phase pipeline |
| `src/domain/*/` | Core domain: Manifest, Template, Context, ConflictResolver |
| `src/infrastructure/*/` | Discovery, Rendering, Prompts, Config, Hooks, Bindings |
| `_templates/<gen>/` | Generator template directories |
| `examples/` | Reference templates for React, Go, Python, YAML |
| `test/` | ReScript tests (`.res` sources → `.res.mjs` artifacts) |
| `test/res/utils/` | Shared test helpers & assertions |
| `openspec/changes/` | SDD change specs |
| `docs/` | Documentation site |

## Conventions

- **ReScript**: PascalCase modules, snake_case values. `//` for comments. `@as("...")` for YAML field aliases.
- **Templates**: EJS `.ejs.t` files with YAML frontmatter (directives: `to`, `inject`, `after`, `before`, `prepend`, `append`, `force`, `sh`)
- **Node >=22** required (import.meta.dirname usage)
- **No npm scripts beyond build/test/bundle** — no lint, typecheck, or format scripts exist
