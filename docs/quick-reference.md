# Quick Reference

LLM-optimized reference. No prose. Public symbols and usage only.

> Language-agnostic — templates output any text (Go, TypeScript, Python, Rust, SQL, YAML, …).

## CLI

```
fluxo init                                         → scaffold .fluxo.yaml
fluxo generate <classification> [--name X] [--force] [--output DIR]
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
attributes   map        CLI --key value pairs
<prompt>     any        Per prompt name
```

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

```
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

## .fluxo.yaml

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
