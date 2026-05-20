# Quick Reference

LLM-optimized reference. No prose. Public symbols and usage only.

> Language-agnostic — templates output any text (Go, TypeScript, Python, Rust, SQL, YAML, …).

## CLI

```
blueprint init                                         → scaffold .blueprint.yaml
blueprint generate <classification> [--name X] [--force] [--output DIR]
```

## manifest.yaml

```yaml
name: <string>
classification: <string>
metadata: {k: v}
prompts:
  - name: <string>
    type: input|select|confirm
    description: <string>
    default: <any>
    options: [<string>]        # required for type:select
```

## Template file frontmatter

```
to:      <path>               # output path
inject:  <regex>              # replace matched
after:   <regex>              # insert after match
before:  <regex>              # insert before match
prepend: true|false           # add to file start
append:  true|false           # add to file end
force:   true|false           # overwrite existing
sh:      <command>            # shell cmd post-render
```

## Context keys

```
cwd          string     Current working directory
actionfolder string     Manifest directory
name         string     Lowercase component name
Name         string     PascalCase component name
names        string     name + "s"
Names        string     Name + "s"
<prompt>     any        Per prompt name
```
*(Note: CLI attributes are merged as individual variables — e.g. --path sets <%= path %>)*

## FuncMaps

```
pascalCase(s)   → HelloWorld
camelCase(s)    → helloWorld
kebabCase(s)    → hello-world
snakeCase(s)    → hello_world
upper(s)        → HELLO
lower(s)        → hello
trim(s)         → stripped
title(s)        → Title Case
```

## Engine public API

```rescript
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

## .blueprint.yaml

```yaml
generators: [{name, classification, template_root, output_root}]
hooks:
  pre_generate: <command>
  post_generate: <command>
  timeout: <duration>   # default 5s
```

## Phase flow

```
Phase0: prompts + conflicts → Phase1: stage + render + inject + shell → Phase2: commit
Rollback: os.RemoveAll(stagingDir) on any Phase1 error
```

## File extensions

`.ejs.t` or `.tmpl` — placed in `files/` relative to `manifest.yaml`.
