# Blueprint ReScript Migration — Technical Design

**Date**: 2026-05-14
**Status**: Draft
**Author**: Senior Architect (GDE & MVP)

---

## 1. Overview

**What**: Migrate Blueprint from Go back to the JavaScript ecosystem, rewritten in ReScript v12.

**Why**: Return Blueprint to the JS ecosystem for better integration with the JS tooling landscape (npm, Node.js), while maintaining its core differentiator — transactional, atomic code generation — with the safety of ReScript's type system.

**Scope**: Full feature parity with the Go version, targeting npm distribution as a standalone CLI tool.

---

## 2. Design Decisions Summary

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Template syntax | EJS (`<%= name %>`) | Hygen-compatible, familiar to JS developers |
| Directory structure | Hygen's `_templates/<gen>/<action>/` | Familiar to Hygen users |
| Transactional safety | Keep 3-phase pipeline | Core differentiator, proven in Go version |
| Prompt system | Keep Blueprint's YAML manifest (`manifest.yaml`) | Declarative, type-safe, no runtime deps |
| Distribution | npm package | Natural for JS ecosystem |
| Config file | Keep `.blueprint.yaml` | Works with YAML manifest system |
| Go codebase | Gradual migration (coexist) | Safer, allows comparison/rollback |
| Scope | Full feature parity | No half-measures |
| Testing | ReScript native tests | Idiomatic, type-safe |
| CLI parsing | `node:util` `parseArgs` | Built into Node.js, zero deps |
| Prompts UI | `node:readline` | Zero extra dependencies |
| Architecture | Pure ReScript + typed bindings | Full type safety across codebase |

---

## 3. Project Structure

```
blueprint/
├── rescript.json                 # ReScript v12 build config
├── package.json                  # npm package metadata, bin entry
├── src/
│   ├── Cli.res                   # CLI entry point
│   ├── Engine.res                # Pipeline orchestrator
│   ├── Manifest.res              # YAML manifest parsing & validation
│   ├── Config.res                # .blueprint.yaml parsing (hooks, settings)
│   ├── Discovery.res             # _templates/ directory traversal
│   ├── Context.res               # Template context: name variants, attributes
│   ├── PromptResolver.res        # Interactive prompt resolution
│   ├── ConflictResolver.res       # Bulk conflict resolution (y/n/s/a)
│   ├── Hooks.res                 # Pre/post generate hook execution
│   │
│   ├── phases/
│   │   ├── Phase0.res            # Prompt collection & conflict detection
│   │   ├── Phase1.res            # Staging, rendering, injection dispatch
│   │   └── Phase2.res            # Atomic commit & rollback
│   │
│   ├── templates/
│   │   ├── Template.res          # Template type definitions & directives
│   │   ├── Frontmatter.res       # YAML frontmatter parsing from .ejs.t files
│   │   ├── Renderer.res          # EJS rendering with funcmaps
│   │   ├── Injection.res         # inject/after/before/prepend/append logic
│   │   └── FuncMap.res           # Case conversion helpers
│   │
│   └── bindings/
│       ├── Ejs.res               # ReScript bindings for EJS
│       ├── Yaml.res              # ReScript bindings for yaml parser
│       ├── ParseArgs.res          # node:util parseArgs bindings
│       ├── Readline.res          # node:readline bindings
│       ├── Fs.res                # node:fs/promises bindings
│       ├── Path.res              # node:path bindings
│       ├── ChildProcess.res       # node:child_process bindings
│       └── Os.res                # node:os bindings
│
├── test/
│   ├── FuncMap_test.res
│   ├── Frontmatter_test.res
│   ├── Manifest_test.res
│   ├── Context_test.res
│   ├── Template_test.res
│   ├── Phase0_test.res
│   ├── Phase1_test.res
│   ├── Phase2_test.res
│   ├── Injection_test.res
│   ├── ConflictResolver_test.res
│   └── Engine_test.res
│
├── _templates/                   # Built-in templates (dogfooding)
│   └── component/
│       └── new/
│           ├── index.tsx.ejs.t
│           └── manifest.yaml
│
└── docs/                         # Documentation
```

---

## 4. Core Types

### 4.1 Template Directives

Templates use EJS syntax (`.ejs.t` files) with YAML frontmatter. Directives are parsed from frontmatter and rendered with EJS.

**Directive variants** (ReScript records):

```rescript
type directive =
  | To(string)                    // target file path
  | Inject(string)                // regex pattern for injection
  | After(string)                 // insert after regex match
  | Before(string)                // insert before regex match
  | Prepend                       // prepend to file start
  | Append                        // append to file end
  | Force                         // overwrite without confirmation
  | Sh(string)                    // shell command after render
```

### 4.2 Template

```rescript
type template = {
  sourcePath: string,
  directives: array<directive>,
  body: string,
}
```

### 4.3 Manifest

```rescript
type promptType = Input | Select | Confirm

type prompt = {
  name: string,
  promptType: promptType,
  description: string,
  default: option<string>,
  options: option<array<string>>,
}

type manifest = {
  name: string,
  classification: string,
  metadata: option<Js.Dict.t<string>>,
  prompts: option<array<prompt>>,
}
```

### 4.4 Context

```rescript
type nameVariants = {
  name: string,
  Name: string,
  names: string,
  Names: string,
}

type context = {
  cwd: string,
  actionfolder: string,
  nameVariants: nameVariants,
  attributes: Js.Dict.t<string>,
}
```

### 4.5 Config

```rescript
type hooksConfig = {
  preGenerate: option<string>,
  postGenerate: option<string>,
  timeout: option<int>,
}

type config = {
  hooks: option<hooksConfig>,
  output: option<string>,
}
```

### 4.6 Pipeline Types

```rescript
type conflict = {
  sourcePath: string,
  targetPath: string,
}

type conflictResolution = Yes | No | Select | Abort

type stageResult = {
  stagingDir: string,
  renderedFiles: array<(string, string)>,
  shellCommands: array<string>,
}

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
}
```

---

## 5. Pipeline Architecture

### 5.1 Three-Phase Transactional Pipeline

```
Phase 0: Resolve
  ├── Parse manifest.yaml
  ├── Resolve interactive prompts (input/select/confirm)
  ├── Merge context: CLI attrs > prompt answers > defaults > name variants
  └── Detect file conflicts in output dir
       ↓ (fail fast if abort)
Phase 1: Stage
  ├── Create temp staging dir (os.tmpdir()/blueprint-<random>)
  ├── For each template:
  │   ├── Parse frontmatter (YAML between --- delimiters)
  │   ├── Render EJS body with merged context
  │   ├── Dispatch on directive:
  │   │   ├── To(path) → write file to staging
  │   │   ├── Inject(regex) → read target, regex replace
  │   │   ├── After(regex) → read target, insert after match
  │   │   ├── Before(regex) → read target, insert before match
  │   │   ├── Prepend → prepend to target
  │   │   ├── Append → append to target
  │   │   └── Sh(cmd) → queue shell command
  │   └── Track (source, target) pair for commit
  └── Execute queued shell commands
       ↓ (on ANY error → rollback: rm -rf stagingDir, exit)
Phase 2: Commit
  ├── Copy all staged files to output root
  ├── Preserve existing files not in conflict
  └── Clean up staging dir
```

### 5.2 Rollback Contract

If Phase 1 fails at any point, `fs.rm(stagingDir, { recursive: true })` is called and the output root is untouched. Phase 2 only runs if Phase 1 succeeds completely.

### 5.3 Conflict Handling

- `force` directive → overwrite silently
- No directive → bulk prompt: `[y]es all / [n]o all / [s]elect / [a]bort`
- `--force` CLI flag → overwrite all silently

### 5.4 Shell Commands

Deferred until all templates render successfully, then executed in order. If any shell command fails, rollback still happens (staging cleaned up, but already-written files in Phase 2 are NOT rolled back — matches Go behavior).

---

## 6. Template Rendering

### 6.1 EJS Binding

```rescript
type ejsOptions = {
  delimiter: option<string>,
  escape: option<string => string>,
}

@module("ejs")
external render: (string, Js.Dict.t<string>, ~options: ejsOptions=?) => string = "render"
```

### 6.2 FuncMap (Template Helpers)

Available in templates as `h.pascalCase(name)` etc.:

| Function | Example |
|----------|---------|
| `pascalCase` | `hello_world` → `HelloWorld` |
| `camelCase` | `hello_world` → `helloWorld` |
| `kebabCase` | `HelloWorld` → `hello-world` |
| `snakeCase` | `HelloWorld` → `hello_world` |
| `upper` | `hello` → `HELLO` |
| `lower` | `HELLO` → `hello` |
| `trim` | strips whitespace |
| `title` | `hello world` → `Hello World` |

The context object passed to EJS: `{ ...nameVariants, ...attributes, h: helpers, cwd, actionfolder }`.

### 6.3 Frontmatter Parsing

Regex-based extraction of YAML between `---` delimiters. The body after the second `---` is the raw EJS template string.

```rescript
type parsedFrontmatter = {
  directives: array<directive>,
  body: string,
}

let parse: string => result<parsedFrontmatter, string>
```

---

## 7. Manifest & Config

### 7.1 Manifest Parsing

Declarative YAML manifest per generator. Validated on parse — `classification` required, each prompt must have non-empty `name` and valid `type`.

```rescript
let parse: string => result<manifest, string>
let validate: manifest => result<unit, string>
```

### 7.2 Config Loading

Looks for `.blueprint.yaml` in current working directory.

```rescript
let load: unit => promise<result<option<config>, string>>
```

### 7.3 Discovery

Finds generators in `_templates/` directory structure. Search paths: `["_templates", "templates", "generators"]` — first match wins per classification.

```rescript
type generator = {
  name: string,
  path: string,
  templates: array<template>,
  manifest: option<manifest>,
}

let discover: (~searchPaths: array<string>=?, unit) => result<array<generator>, string>
```

---

## 8. CLI Interface

### 8.1 Commands

```
blueprint init                          # scaffold .blueprint.yaml
blueprint generate <classification>     # run pipeline
  --name <name>                     # component name
  --force                           # skip prompts, overwrite
  --output <dir>                    # output directory (default: "generated")
  --<key> <value>                  # arbitrary attributes passed to templates
```

### 8.2 CLI Parsing

`node:util` `parseArgs` — zero extra dependencies.

```rescript
type optionConfig = {
  \"type": string,
  short: option<string>,
  default: option<Js.Json.t>,
}

type parseArgsConfig = {
  args: option<array<string>>,
  options: option<Js.Dict.t<optionConfig>>,
  strict: option<bool>,
  allowPositionals: option<bool>,
}

type parsedArgs = {
  values: Js.Dict.t<Js.Json.t>,
  positionals: array<string>,
}

@module("node:util")
external parseArgs: parseArgsConfig => parsedArgs = "parseArgs"
```

### 8.3 Entry Point Flow

```
Cli.res
  ├── parse CLI args via parseArgs
  ├── dispatch: init | generate
  │   ├── init → write default .blueprint.yaml
  │   └── generate →
  │       ├── Config.load() → get hooks, output dir
  │       ├── Discovery.discover() → find generator
  │       ├── Manifest.parse() + validate()
  │       ├── Context.build(name, attributes, manifest)
  │       ├── Engine.run(generator, context, config)
  │       └── print summary
  └── handle errors → print + exit 1
```

---

## 9. Dependencies

### 9.1 Runtime Dependencies

| Package | Purpose |
|---------|---------|
| `ejs` | Template rendering |
| `yaml` | YAML parsing for manifests and config |
| `@rescript/runtime` | ReScript v12 runtime |

### 9.2 Dev Dependencies

| Package | Purpose |
|---------|---------|
| `rescript` | ReScript v12 compiler |
| `rescript-test` | ReScript native test framework |

### 9.3 Node.js Built-ins (No Dependencies)

| Module | Purpose |
|--------|---------|
| `node:util` | `parseArgs` for CLI |
| `node:fs/promises` | File I/O |
| `node:path` | Path manipulation |
| `node:child_process` | Shell command execution |
| `node:os` | `tmpdir()` for staging |
| `node:readline` | Interactive prompts |

**Minimal dependency count**: 2 runtime packages — matches Go version's philosophy.

---

## 10. Testing Strategy

### 10.1 Test Framework

ReScript native tests (`rescript-test`).

### 10.2 Test Categories

**Unit tests** (each module independently):
- `FuncMap_test.res`: all case conversions, edge cases (empty, single char, unicode)
- `Frontmatter_test.res`: valid/invalid frontmatter, unknown directives, missing `---`
- `Manifest_test.res`: parse valid manifest, missing fields, invalid types
- `Context_test.res`: name variant generation, attribute merge priority
- `Template_test.res`: directive parsing from YAML frontmatter

**Integration tests** (pipeline phases):
- `Phase0_test.res`: prompt resolution, conflict detection
- `Phase1_test.res`: EJS rendering, injection modes, shell queue
- `Phase2_test.res`: atomic commit, staging cleanup
- `Injection_test.res`: each injection mode with real file content

**End-to-end tests**:
- `Engine_test.res`: full generate pipeline, verify output files
- Conflict resolution: existing files + force flag + interactive selection
- Rollback: failing template, verify output root untouched

### 10.3 Test Data

`test/testdata/` directory with sample manifests, templates, and expected outputs — mirrors the Go `testdata/integration/` approach.

---

## 11. Migration Strategy

### Phase 1: Project Setup
- Create `rescript.json`, `package.json`, `src/`, `test/`
- Go code stays untouched in `cmd/`, `internal/`
- Both coexist — different build systems, no conflict

### Phase 2: Bindings Layer
- All bindings in `src/bindings/`: Ejs, Yaml, ParseArgs, Readline, Fs, Path, ChildProcess, Os
- Pure domain types in separate modules (no bindings dependencies)

### Phase 3: Core Modules
- FuncMap (case conversions)
- Frontmatter parser
- Discovery
- Manifest parser + validator
- Config loader
- Context builder

### Phase 4: Pipeline Phases
- Phase0 (prompts)
- Phase1 (rendering + injection)
- Phase2 (commit)
- Hooks
- ConflictResolver

### Phase 5: Engine & CLI
- Engine (orchestrator)
- Cli.res entry point

### Phase 6: Testing & Validation
- Port Go test cases to ReScript
- Verify with real templates
- Benchmark against Go version

### Phase 7: Publish
- Update docs for ReScript version
- Publish to npm as `blueprint`
- Deprecation notice on Go version when ready

---

## 12. Key Differences from Go Version

| Aspect | Go Version | ReScript Version |
|--------|-----------|------------------|
| Template syntax | Go `text/template` `{{ }}` | EJS `<%= %>` |
| Directory structure | `templates/<classification>/` | `_templates/<gen>/<action>/` |
| Manifest | `manifest.yaml` (same) | `manifest.yaml` (same) |
| Config | `.blueprint.yaml` (same) | `.blueprint.yaml` (same) |
| CLI parsing | Go `flag` | `node:util` `parseArgs` |
| Prompts | Go stdin readline | `node:readline` |
| YAML parsing | `gopkg.in/yaml.v3` | `yaml` npm package |
| Distribution | `go install` / binary | npm package |
| Runtime deps | 1 (`yaml`) | 2 (`ejs` + `yaml`) |
| Type safety | Go static types | ReScript static types |

---

## 13. Open Questions

None — all decisions resolved during design phase.
