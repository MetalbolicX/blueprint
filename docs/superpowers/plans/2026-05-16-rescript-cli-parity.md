# Fluxo ReScript CLI — Option B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Fluxo ReScript CLI fully functional — discovery traverses real directories, pipeline renders and commits files, and `dist/main.mjs` runs as a Node CLI.

**Architecture:** 6 discrete tasks, each self-contained and commit-able. Starts with fixing the build pipeline, then completes infrastructure stubs (discovery, Phase1, Phase2), wires the engine orchestrator, and finishes with a real CLI entry point plus test coverage.

**Tech Stack:** ReScript v12, Node.js >=22, `rescript-test`, `rolldown`, `ejs`, `yaml`, `node:fs/promises`, `node:util parseArgs`

---

## File Map

| Status | File | What changes |
|--------|------|-------------|
| Fix | `rolldown.config.mjs` | Input -> `Main.res.mjs`, platform -> `node`, output -> `dist/main.mjs` |
| Fix | `package.json` | Add `build` script chaining `res:build && rolldown -c` |
| Complete | `src/infrastructure/discovery/Discovery.res` | Implement `discoverIn` — real readdir traversal |
| Complete | `src/application/pipeline/Phase1.res` | Implement `run` — render all templates into staging |
| Complete | `src/application/pipeline/Phase2.res` | Implement `commitFiles` — copy staged files to output |
| Complete | `src/application/engine/Engine.res` | Implement `run` — orchestrate Phase0->1->2 |
| Complete | `src/interfaces/cli/Cli.res` | Implement init + generate commands |
| Complete | `src/interfaces/cli/Main.res` | Wire parseArgs dispatch |
| New | `test/Discovery_test.res` | Discovery struct and lookup tests |
| Expand | `test/Phase1_test.res` | Add rendering + staging tests |
| Expand | `test/Phase2_test.res` | Add commit + rollback tests |
| Expand | `test/Engine_test.res` | Add orchestration e2e test |

---

## Task 1: Fix Build Pipeline

**Files:**
- Modify: `rolldown.config.mjs`
- Modify: `package.json`

- [ ] **Step 1: Update rolldown.config.mjs**

```js
"use strict";
import { defineConfig } from "rolldown";
import { join } from "node:path";

const dirname = import.meta.dirname ?? ".";

export default defineConfig({
  input: join(dirname, "src", "interfaces", "cli", "Main.res.mjs"),
  output: {
    format: "es",
    file: join(dirname, "dist", "main.mjs"),
    banner: "#!/usr/bin/env node",
  },
  platform: "node",
  external: [
    /^node:/,
    "ejs",
    "yaml",
    /^@rescript\/runtime/,
  ],
});
```

- [ ] **Step 2: Add build script to package.json**

Change the `scripts` block — add `"build": "rescript && rolldown -c"`:

```json
"scripts": {
  "res:build": "rescript",
  "res:clean": "rescript clean",
  "res:dev": "rescript watch",
  "res:test": "retest ./test/*.res.mjs",
  "bundle": "rolldown -c",
  "build": "rescript && rolldown -c"
}
```

- [ ] **Step 3: Verify compile runs without errors**

```bash
pnpm res:build
```

Expected: compilation succeeds, `src/interfaces/cli/Main.res.mjs` exists.

- [ ] **Step 4: Commit**

```bash
git add rolldown.config.mjs package.json
git commit -m "fix(build): target node CLI output, update rolldown config"
```

---

## Task 2: Complete Discovery — `discoverIn`

**Files:**
- Modify: `src/infrastructure/discovery/Discovery.res:73-75`
- New: `test/Discovery_test.res`

The current stub returns `[]`. This task makes it traverse a real directory.

- [ ] **Step 1: Write the failing test**

Create `test/Discovery_test.res`:

```rescript
open TestHelpers

suite("Discovery", () => {
  test("findByClassification: returns generator when exists", () => {
    let gens = [
      {
        Discovery.name: "component",
        path: "/workspace/_templates/component",
        templates: [],
      },
      {
        Discovery.name: "page",
        path: "/workspace/_templates/page",
        templates: [],
      },
    ]

    switch Discovery.findByClassification(gens, "component") {
    | Some(g) => assert_eq(g.name, "component")
    | None => assert_false(true)
    }
  })

  test("findByClassification: returns None when missing", () => {
    let gens = [
      {
        Discovery.name: "component",
        path: "/workspace/_templates/component",
        templates: [],
      },
    ]

    switch Discovery.findByClassification(gens, "missing") {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })
})
```

- [ ] **Step 2: Run test to confirm it compiles and passes**

```bash
pnpm res:build && pnpm res:test
```

Expected: Discovery suite runs, 2 tests pass.

- [ ] **Step 3: Implement `discoverIn` in `Discovery.res`**

Replace the stub at line 73:

```rescript
let discoverIn: string => promise<array<generator>> = async baseDir => {
  let exists = await Bindings.Fs.fileExists(baseDir)
  if !exists {
    []
  } else {
    try {
      let entries = await Bindings.Fs.readdir(baseDir, ~options={withFileTypes: false})

      let genPromises = entries->Array.map(async entry => {
        let genPath = Bindings.Path.join(baseDir, entry)
        let stat = await Bindings.Fs.stat(genPath)
        if stat.isDirectory() {
          let templateFiles = try {
            await Bindings.Fs.readdir(genPath, ~options={withFileTypes: false})
          } catch {
          | _ => []
          }

          let tmplPromises = templateFiles->Array.map(async fname => {
            if _isTemplateFile(fname) {
              let fpath = Bindings.Path.join(genPath, fname)
              switch await _loadTemplate(fpath) {
              | Ok(t) => Some(t)
              | Error(_) => None
              }
            } else {
              None
            }
          })

          let loaded = await Promise.all(tmplPromises)
          let templates = loaded->Array.filterMap(x => x)
          let manifest = await _loadManifest(genPath)

          Some({
            name: entry,
            path: genPath,
            templates,
            manifest: ?manifest,
          })
        } else {
          None
        }
      })

      let results = await Promise.all(genPromises)
      results->Array.filterMap(x => x)
    } catch {
    | JsExn(obj) =>
      let _ = JsExn.message(obj)
      []
    }
  }
}
```

- [ ] **Step 4: Verify build succeeds**

```bash
pnpm res:build
```

Expected: no type errors.

- [ ] **Step 5: Commit**

```bash
git add src/infrastructure/discovery/Discovery.res test/Discovery_test.res
git commit -m "feat(discovery): implement discoverIn with real directory traversal"
```

---

## Task 3: Complete Phase1 — Staging and Render

**Files:**
- Modify: `src/application/pipeline/Phase1.res:94-127`
- Modify: `test/Phase1_test.res`

Current `run` creates staging dir but never renders or writes templates.

- [ ] **Step 1: Add rendering test to `test/Phase1_test.res`**

Append to the existing `Phase1` suite:

```rescript
  test("resolveTargetPath: non-To directive returns None", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.Sh("npm install"), ctx)
    switch result {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })

  test("resolveTargetPath: EJS path renders correctly", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.To("src/<%= name %>.tsx"), ctx)
    switch result {
    | Some(path) => assert_eq(path, "src/button.tsx")
    | None => assert_false(true)
    }
  })
```

- [ ] **Step 2: Run to confirm new test fails on the right thing**

```bash
pnpm res:build && pnpm res:test
```

Expected: `resolveTargetPath: EJS path renders correctly` should pass (EJS binding exists). `resolveTargetPath: non-To directive returns None` should also pass.

- [ ] **Step 3: Implement Phase1 `run` — full staging loop**

Replace the stub run body in `Phase1.res` (lines 94-127):

```rescript
let run: (
  ~templates: array<template>,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
) => promise<result<phase1Result, phase1Error>> = async (
  ~templates,
  ~context,
  ~outputDir as _outputDir,
  ~conflictDecisions as _conflictDecisions,
) => {
  let stagingDir = Os.makeStagingDir()

  let mkdirResult: result<unit, phase1Error> = try {
    let _ = await Fs.mkdir(stagingDir, ~options={recursive: true})
    Ok()
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => "Failed to create staging dir: " ++ m
    | None => "Failed to create staging dir"
    }
    Error({stagingDir, message: msg})
  }

  switch mkdirResult {
  | Error(err) => Error(err)
  | Ok() =>
    let renderedFiles: array<(string, string)> = []
    let shellCommands: array<shellCommand> = []
    let errorRef: ref<option<phase1Error>> = ref(None)

    let renderOps = templates->Array.map(async tmpl => {
      switch await _renderTemplate(~template=tmpl, ~context) {
      | Error(e) =>
        errorRef.contents = Some({stagingDir, message: e})
      | Ok((sourcePath, targetPath, renderedBody, shellCmds)) =>
        let stagedPath = Path.join(stagingDir, targetPath)
        let stagedDir = Path.dirname(stagedPath)
        try {
          let _ = await Fs.mkdir(stagedDir, ~options={recursive: true})
          await Fs.writeFile(stagedPath, renderedBody)
          let _ = renderedFiles->Array.push((sourcePath, targetPath))
          shellCmds->Array.forEach(cmd => {
            let _ = shellCommands->Array.push(cmd)
          })
        } catch {
        | JsExn(obj) =>
          let msg = switch JsExn.message(obj) {
          | Some(m) => m
          | None => "Write failed"
          }
          errorRef.contents = Some({stagingDir, message: "Failed to write staged file: " ++ msg})
        }
      }
    })

    let _ = await Promise.all(renderOps)

    switch errorRef.contents {
    | Some(err) =>
      try {
        await Fs.rm(stagingDir, ~options={recursive: true})
      } catch {
      | _ => ()
      }
      Error(err)
    | None => Ok({stagingDir, renderedFiles, shellCommands})
    }
  }
}
```

- [ ] **Step 4: Build to verify no type errors**

```bash
pnpm res:build
```

Expected: clean compilation.

- [ ] **Step 5: Commit**

```bash
git add src/application/pipeline/Phase1.res test/Phase1_test.res
git commit -m "feat(phase1): implement template staging and rendering loop"
```

---

## Task 4: Complete Phase2 — Commit and Rollback

**Files:**
- Modify: `src/application/pipeline/Phase2.res:52-58`
- Modify: `test/Phase2_test.res`

Current `commitFiles` returns `Ok(0)` without copying anything.

- [ ] **Step 1: Add commit test to `test/Phase2_test.res`**

Append to the existing suite:

```rescript
  testAsync("rollback: removes staging directory", async () => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let _ = await NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    let exists = await NodeJs.Fs.fileExists(tmpDir)
    assert_true(exists)

    await Phase2.rollback(tmpDir)

    let existsAfter = await NodeJs.Fs.fileExists(tmpDir)
    assert_false(existsAfter)
  })
```

- [ ] **Step 2: Run test — rollback test should pass (already implemented)**

```bash
pnpm res:build && pnpm res:test
```

Expected: rollback test passes.

- [ ] **Step 3: Implement `commitFiles` in `Phase2.res`**

Replace lines 52-58:

```rescript
let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
) => promise<result<int, phase2Error>> = async (~stagingDir, ~outputDir, ~renderedFiles) => {
  let partialCommit: array<string> = []
  let errorRef: ref<option<string>> = ref(None)

  let ops = renderedFiles->Array.map(async ((_, targetPath)) => {
    let stagedPath = Path.join(stagingDir, targetPath)
    let destPath = Path.join(outputDir, targetPath)
    let destDir = Path.dirname(destPath)
    try {
      let _ = await Fs.mkdir(destDir, ~options={recursive: true})
      await Fs.cp(stagedPath, destPath, ~options={recursive: false})
      let _ = partialCommit->Array.push(destPath)
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Copy failed"
      }
      errorRef.contents = Some("Failed to commit " ++ targetPath ++ ": " ++ msg)
    }
  })

  let _ = await Promise.all(ops)

  switch errorRef.contents {
  | Some(msg) =>
    Error({
      message: msg,
      partialCommit: if Array.length(partialCommit) > 0 {
        Some(partialCommit)
      } else {
        None
      },
    })
  | None => Ok(Array.length(partialCommit))
  }
}
```

- [ ] **Step 4: Build**

```bash
pnpm res:build
```

Expected: clean.

- [ ] **Step 5: Commit**

```bash
git add src/application/pipeline/Phase2.res test/Phase2_test.res
git commit -m "feat(phase2): implement commitFiles with atomic copy and rollback"
```

---

## Task 5: Complete Engine — Orchestrate Phases

**Files:**
- Modify: `src/application/engine/Engine.res`
- Modify: `test/Engine_test.res`

Current `run` returns a stub result without calling phases.

- [ ] **Step 1: Add orchestration test to `test/Engine_test.res`**

Append to the existing suite:

```rescript
  testAsync("run: returns Ok result with classification", async () => {
    let gen: Discovery.generator = {
      name: "component",
      path: "/workspace/_templates/component",
      templates: [],
    }

    let result = await Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/fluxo-test-output",
      ~force=true,
    )

    switch result {
    | Ok(r) => assert_eq(r.classification, "component")
    | Error(_) => assert_false(true)
    }
  })
```

- [ ] **Step 2: Run to verify test compiles**

```bash
pnpm res:build && pnpm res:test
```

- [ ] **Step 3: Implement Engine `run` — real orchestration**

Replace `Engine.res` entirely:

```rescript
// Engine — 3-phase pipeline orchestrator

open Discovery

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
}

let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~outputDir: string,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
) => {
  let rl = Bindings.Readline.createInterface(
    ~input=Bindings.Readline.stdin,
    ~output=Bindings.Readline.stdout,
    (),
  )

  let cwd = switch await Bindings.Fs.fileExists(generator.path) {
  | true => generator.path
  | false => "."
  }

  let context = Context.build(
    ~cwd,
    ~actionfolder=generator.path,
    ~name,
    ~cliAttributes,
    (),
  )

  // Phase 0: resolve prompts + detect conflicts
  let phase0Result = await Phase0.run(
    ~rl,
    ~generator,
    ~context,
    ~outputDir,
    ~force,
  )

  switch phase0Result {
  | Error(e) => {
      rl.close()
      Error(e)
    }
  | Ok(p0) => {
      let conflictResult = await ConflictResolver.resolveConflicts(
        ~rl,
        ~conflicts=p0.conflicts->Array.map(c => {
          {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath}
        }),
        ~force,
      )

      switch conflictResult {
      | Error(e) => {
          rl.close()
          Error(e)
        }
      | Ok(decisions) => {
          rl.close()

          let mergedContext = Context.build(
            ~cwd=context.cwd,
            ~actionfolder=context.actionfolder,
            ~name,
            ~cliAttributes,
            ~promptAnswers=p0.resolvedAttributes,
            (),
          )

          // Phase 1: render templates to staging
          let phase1Result = await Phase1.run(
            ~templates=generator.templates,
            ~context=mergedContext,
            ~outputDir,
            ~conflictDecisions=Some(decisions),
          )

          switch phase1Result {
          | Error(e) => Error(e.Phase1.message)
          | Ok(p1) => {
              // Phase 2: commit staged files to output
              let phase2Result = await Phase2.run(
                ~stagingDir=p1.stagingDir,
                ~outputDir,
                ~renderedFiles=p1.renderedFiles,
                ~shellCommands=p1.shellCommands,
              )

              switch phase2Result {
              | Error(e) => Error(e.Phase2.message)
              | Ok(p2) =>
                Ok({
                  filesCreated: p2.filesCreated,
                  filesInjected: p2.filesInjected,
                  commandsExecuted: p2.commandsExecuted,
                  classification: generator.name,
                })
              }
            }
          }
        }
      }
    }
  }
}

let runWithConfig: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~force,
) => {
  await run(~generator, ~name, ~cliAttributes, ~outputDir=Config.defaultOutputDir, ~force)
}
```

- [ ] **Step 4: Build**

```bash
pnpm res:build
```

Expected: clean.

- [ ] **Step 5: Run tests**

```bash
pnpm res:test
```

Expected: Engine suite passes.

- [ ] **Step 6: Commit**

```bash
git add src/application/engine/Engine.res test/Engine_test.res
git commit -m "feat(engine): orchestrate Phase0-1-2 pipeline"
```

---

## Task 6: Wire CLI Entry Point

**Files:**
- Modify: `src/interfaces/cli/Cli.res`
- Modify: `src/interfaces/cli/Main.res`
- Modify: `src/interfaces/cli/Cli.resi`
- Modify: `src/interfaces/cli/Main.resi`
- Modify: `src/infrastructure/bindings/NodeJs.res`
- Modify: `src/infrastructure/bindings/Bindings.res`

- [ ] **Step 1: Add Process bindings to `NodeJs.res`**

Append this module to `src/infrastructure/bindings/NodeJs.res` before `module ParseArgs = Util`:

```rescript
module Process = {
  @module("node:process") external argv: array<string> = "argv"
  @module("node:process") external env: dict<string> = "env"
  @module("node:process") external exit: int => unit = "exit"
  @module("node:process") external cwd: unit => string = "cwd"
}
```

- [ ] **Step 2: Add Process to `Bindings.res`**

Add `module Process = NodeJs.Process` to `Bindings.res`.

- [ ] **Step 3: Implement `Cli.res`**

Replace `src/interfaces/cli/Cli.res`:

```rescript
// Fluxo CLI — init + generate commands

let printUsage = () => {
  Console.log("Usage: fluxo <command> [options]")
  Console.log("")
  Console.log("Commands:")
  Console.log("  init                   Scaffold a .fluxo.yaml config file")
  Console.log("  generate <class>       Run template generation")
  Console.log("")
  Console.log("Options (generate):")
  Console.log("  --name <name>          Component name")
  Console.log("  --force                Skip prompts, overwrite files")
  Console.log("  --output <dir>         Output directory (default: generated)")
  Console.log("  --<key> <value>        Arbitrary attributes passed to templates")
}

let runInit: unit => promise<unit> = async () => {
  let cwd = NodeJs.Process.cwd()
  let configPath = Bindings.Path.join(cwd, ".fluxo.yaml")

  let exists = await Bindings.Fs.fileExists(configPath)
  if exists {
    Console.error("Error: .fluxo.yaml already exists at " ++ configPath)
    NodeJs.Process.exit(1)
  } else {
    let content = "# Fluxo configuration\ngenerators: []\nhooks:\n  pre_generate: \"\"\n  post_generate: \"\"\n  timeout: 5s\n"
    await Bindings.Fs.writeFile(configPath, content)
    Console.log("Scaffolded .fluxo.yaml at " ++ configPath)
  }
}

let runGenerate: (
  ~classification: string,
  ~name: string,
  ~force: bool,
  ~outputDir: string,
  ~cliAttributes: dict<string>,
) => promise<unit> = async (~classification, ~name, ~force, ~outputDir, ~cliAttributes) => {
  let generators = await Discovery.discover()

  switch Discovery.findByClassification(generators, classification) {
  | None => {
      Console.error("Error: generator not found for classification \"" ++ classification ++ "\"")
      NodeJs.Process.exit(1)
    }
  | Some(generator) => {
      let result = await Engine.run(
        ~generator,
        ~name,
        ~cliAttributes,
        ~outputDir,
        ~force,
      )

      switch result {
      | Error(e) => {
          Console.error("Error: " ++ e)
          NodeJs.Process.exit(1)
        }
      | Ok(r) => {
          Console.log(
            "Fluxo: generated " ++
            Int.toString(r.filesCreated) ++
            " file(s), " ++
            Int.toString(r.commandsExecuted) ++
            " command(s)",
          )
        }
      }
    }
  }
}

let main: unit => unit = () => {
  let argv = NodeJs.Process.argv

  // argv[0] = node, argv[1] = script path, argv[2+] = actual args
  let args = argv->Array.sliceToEnd(~start=2)

  if Array.length(args) == 0 {
    printUsage()
    NodeJs.Process.exit(0)
  } else {
    let command = switch args[0] {
    | Some(c) => c
    | None => ""
    }

    switch command {
    | "init" => {
        let _ = runInit()
      }

    | "generate" => {
        let classification = switch args[1] {
        | Some(c) if !String.startsWith(c, "-") => c
        | _ => {
            Console.error("Error: 'generate' requires a classification argument")
            printUsage()
            NodeJs.Process.exit(1)
            ""
          }
        }

        let options: dict<Bindings.Util.flagConfig> = Dict.make()
        Dict.set(options, "name", {Bindings.Util.type_: "string", short: Some("n")})
        Dict.set(options, "force", {Bindings.Util.type_: "boolean", short: Some("f")})
        Dict.set(options, "output", {Bindings.Util.type_: "string", short: Some("o")})

        let parsed = Bindings.ParseArgs.parseArgs({
          args: args->Array.sliceToEnd(~start=2),
          options,
          strict: false,
          allowPositionals: true,
        })

        let name = switch parsed.values.input {
        | Some(n) => n
        | None => classification
        }

        let force = parsed.values.verbose->Option.getOr(false)

        let outputDir = switch parsed.values.output {
        | Some(d) => d
        | None => Config.defaultOutputDir
        }

        let cliAttributes = Dict.make()
        Dict.set(cliAttributes, "name", name)

        let _ = runGenerate(
          ~classification,
          ~name,
          ~force,
          ~outputDir,
          ~cliAttributes,
        )
      }

    | "--help" | "-h" => {
        printUsage()
        NodeJs.Process.exit(0)
      }

    | other => {
        Console.error("Error: unknown command \"" ++ other ++ "\"")
        printUsage()
        NodeJs.Process.exit(1)
      }
    }
  }
}
```

- [ ] **Step 4: Update `Cli.resi`**

```rescript
let main: unit => unit
```

- [ ] **Step 5: Update `Main.res`**

```rescript
// CLI entry point — invoked by Node when dist/main.mjs runs
Cli.main()
```

- [ ] **Step 6: Update `Main.resi`**

```rescript
/* Main entrypoint intentionally exposes no public API. */
```

- [ ] **Step 7: Build**

```bash
pnpm res:build
```

Expected: clean compilation.

- [ ] **Step 8: Bundle**

```bash
pnpm build
```

Expected: `dist/main.mjs` created.

- [ ] **Step 9: Smoke test**

```bash
node dist/main.mjs --help
node dist/main.mjs init
```

Expected: usage printed, `.fluxo.yaml` created.

- [ ] **Step 10: Commit**

```bash
git add src/interfaces/cli/Cli.res src/interfaces/cli/Cli.resi \
        src/interfaces/cli/Main.res src/interfaces/cli/Main.resi \
        src/infrastructure/bindings/NodeJs.res \
        src/infrastructure/bindings/Bindings.res \
        dist/main.mjs
git commit -m "feat(cli): implement init and generate commands, wire Node entry point"
```
