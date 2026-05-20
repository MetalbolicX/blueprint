# Plan: Fix stale Go references in docs

## Problem

The codebase was migrated from Go to ReScript, but 4 user-facing docs files still contain references to Go (text/template, Go-based, Go regexp) that are incorrect/misleading.

## Changes

### 1. `docs/README.md:3`

```diff
- Fast, transactional, Go-based template generator — a modern Hygen replacement.
+ Fast, transactional template generator — a modern Hygen replacement.
```

### 2. `docs/api-reference.md:130` (FuncMaps section header)

```diff
- Template helper functions registered in Go `text/template`.
+ Template helper functions available via the `h.*` prefix in EJS templates.
```

### 3. `docs/quick-reference.md:68-84` (Engine public API section)

Replace the entire Go-style signatures block with actual ReScript module signatures:

Current (stale):
```
## Engine public API

engine.Execute(ctx, manifestPath, outputRoot, ...ContextInput) -> (*Result, error)
  ContextInput{CWD, Name, ManifestPath, Attributes map[string]string}
  Result{CommittedFiles []string, InjectionLog []InjectionResult}

manifest.Parse(yamlBytes []byte) -> (*Manifest, error)
discovery.Discover(root) -> (TemplateIndex, error)
templates.ParseFrontmatter(content) -> (*Directives, body, error)
templates.ApplyInjection(target, pattern, content, mode) -> (string, error)
templates.RegisterFuncMaps() -> template.FuncMap
phase0.Execute(input) -> (*Phase0Output, error)
phase1.Execute(input) -> (*Phase1Output, error)
phase2.Execute(input) -> (*Phase2Output, error)
hooks.ExecuteHooks(config, phase) -> error
conflicts.Resolver{BulkResolve(conflicts)} -> (map[string]bool, error)
```

Replacement:
```
## Engine public API

Engine.run(~generator, ~name, ~cliAttributes, ~outputDir, ~force, ~config=?)
  => promise<result<generateResult, string>>
  generateResult: {filesCreated, filesInjected, commandsExecuted, classification}

Manifest.parse(str) => result<manifest, string>
  manifest: {name, classification, metadata?, prompts?}

Discovery.discover(~searchPaths=?, unit) => promise<array<generator>>
  generator: {name, path, templates, manifest?}

Frontmatter.parse(str) => result<{directives, body}, string>
Injection.apply(~existingContent, ~renderedContent, ~directive)
  => result<{content, applied}, string>
Renderer.render(template, context) => result<string, string>
FuncMap.makeHelpers() => helpers

Phase0.run(~rl, ~generator, ~context, ~outputDir, ~force)
  => promise<result<phase0Result, string>>
Phase1.run(~templates, ~context, ~outputDir, ~conflictDecisions, ~shellConfig=?)
  => promise<result<phase1Result, phase1Error>>
Phase2.run(~stagingDir, ~outputDir, ~renderedFiles, ~shellCommands, ~shellConfig=?)
  => promise<result<phase2Result, phase2Error>>
Phase2.rollback(stagingDir) => promise<unit>

Hooks.run(~config, ~projectRoot, ~hookType, ~shellConfig=?)
  => promise<result<unit, string>>

Context.build(~cwd, ~actionfolder, ~name, ~cliAttributes=?, ~promptAnswers=?,
             ~manifestDefaults=?, unit) => context

Config.loadFrom(path) => promise<result<option<config>, string>>
Config.loadGlobal() => promise<result<option<globalConfig>, string>>

ConflictResolver.resolveConflicts(~rl, ~conflicts, ~force)
  => promise<result<array<conflictDecision>, string>>

PromptResolver.resolve(~rl, ~prompts, ~force, ~baseContext)
  => promise<result<dict<string>, resolveError>>
```

### 4. `docs/tutorials.md:262`

```diff
- The `after` and `before` patterns are compiled as Go regexp.
+ The `after` and `before` patterns are compiled as JavaScript regex.
```

## Files NOT modified

- `docs/architecture.md` — already up to date (EJS, dist/main.mjs)
- `docs/setup.md` — never mentioned Go
- `README.md` (root) — never mentioned Go
- Historical docs (`blueprint-handoff-*`, `hygen-architecture-*`, `superpowers/`) — document the Go version as historical context, leave as-is

## Verification

After changes, grep for `Go`, `Go-based`, `text/template`, `template.FuncMap` in `docs/*.md` — should return zero matches in user-facing docs (only hits in historical handoff docs and superpowers/).
