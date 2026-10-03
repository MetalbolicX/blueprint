open Context

type packageMetadata = {version: string}
@val external parsePackageMetadata: string => packageMetadata = "JSON.parse"

let importMetaUrl: string = %raw("import.meta.url")
@module("node:url") external fileURLToPath: string => string = "fileURLToPath"

// Extract the "name" field of a manifest without crashing on garbage input.
let packageNameFromJson: string => string = %raw(`
  function(content) {
    try { const parsed = JSON.parse(content); return typeof parsed.name === "string" ? parsed.name : ""; }
    catch (_) { return ""; }
  }
`)

// Match this package's manifest regardless of npm scope ("blueprint" or
// "@scope/blueprint"): we only ever walk up from inside our own package.
let isBlueprintName = (name: string): bool => name == "blueprint" || String.endsWith(name, "/blueprint")

// Walk up from startDir looking for this package's own manifest. argv[1] is
// unusable here: under npx / node_modules/.bin / npm-global installs it is a
// symlink path whose dirname is NOT the package root, so an argv-based
// lookup resolves the wrong package.json and exits 1 (found in review).
let rec findPackageJson = (
  currentDir: string,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~depth: int=0,
): promise<option<string>> => {
  if depth > 6 {
    Promise.resolve(None)
  } else {
    let candidate = path.join(currentDir, "package.json")
    let parent = path.dirname(currentDir)
    fs.readFile(candidate, ~options={encoding: "utf8"})
    ->Promise.then(content =>
        if packageNameFromJson(content)->isBlueprintName {
          Promise.resolve(Some(candidate))
        } else if parent == currentDir {
          Promise.resolve(None)
        } else {
          findPackageJson(parent, ~fs, ~path, ~depth=depth + 1)
        }
      )
    ->Promise.catch(_ =>
      parent == currentDir ? Promise.resolve(None) : findPackageJson(parent, ~fs, ~path, ~depth=depth + 1)
    )
  }
}

// Known CLI flags that should NOT be collected as template attributes.
let knownFlags: array<string> = ["name", "force", "output", "help"]

let _isKnownFlag: string => bool = key => {
  let found = ref(false)
  knownFlags->Array.forEach(f => {
    if f == key { found := true }
  })
  found.contents
}

/**
 * Checks whether a CLI flag (both long `--name` and short `-f` forms) is
 * present in the argument list.
 */
let parseCommandFlag = (args: array<string>, ~name: string): bool => {
  let long = "--" ++ name
  let short = "-" ++ Js.String.slice(~from=0, ~to_=1, name)
  args->Array.includes(long) || args->Array.includes(short)
}

/**
 * Extracts template attributes from CLI flag arguments.
 * Parses `--key=value`, `--key value`, and `--key` (boolean true) patterns.
 * Stops parsing at `--` terminator.
 * Skips known CLI flags (name, force, output, help).
 */
let extractAttributes: (~args: array<string>) => dict<Context.attrValue> = (~args) => {
  let result: dict<Context.attrValue> = Dict.make()
  let len = Array.length(args)
  let i = ref(0)

  while i.contents < len {
    let arg = Array.getUnsafe(args, i.contents)
    if arg == "--" {
      i := len
    } else if String.startsWith(arg, "--") {
      let eqIdx = String.indexOf(arg, "=")
      let key = if eqIdx >= 0 {
        String.slice(arg, ~start=2, ~end=eqIdx)
      } else {
        String.slice(arg, ~start=2)
      }
      let isKnown = _isKnownFlag(key)
      if !isKnown {
        let value = if eqIdx >= 0 {
          String.slice(arg, ~start=eqIdx + 1)
        } else if i.contents + 1 < len && !String.startsWith(Array.getUnsafe(args, i.contents + 1), "-") {
          i := i.contents + 1
          Array.getUnsafe(args, i.contents)
        } else {
          "true"
        }
        switch Dict.get(result, key) {
        | Some(Values(existing)) => Dict.set(result, key, Values(existing->Array.concat([value])))
        | Some(Scalar(existing)) => Dict.set(result, key, Values([existing, value]))
        | None => Dict.set(result, key, Scalar(value))
        }
      }
    }
    i := i.contents + 1
  }
  result
}

// ─── Per-command handlers ─────────────────────────────────────────────────────

let routeVersion: (~deps: Ports.deps) => promise<unit> = async (~deps) => {
  // Resolve from this module's URL, never argv[1]: installed bins invoke the
  // bundle through a node_modules/.bin symlink, and the old argv-based path
  // landed on a foreign package.json and failed with ENOENT.
  let entryDir = try {
    deps.path.dirname(fileURLToPath(importMetaUrl))
  } catch {
  | _ =>
    deps.process
    .argv()
    ->Array.get(1)
    ->Option.getOr("dist/main.mjs")
    ->(entry => deps.path.dirname(entry))
  }
  switch await findPackageJson(entryDir, ~fs=deps.fs, ~path=deps.path) {
  | Some(packagePath) => {
      let packageJson = await deps.fs.readFile(packagePath, ~options={encoding: "utf8"})
      let metadata = parsePackageMetadata(packageJson)
      Console.log("Blueprint " ++ metadata.version)
      deps.process.exit(0)
    }
  | None => {
      Console.error("Could not locate the blueprint package.json from " ++ entryDir)
      deps.process.exit(1)
    }
  }
}

let routeReadyz: (~deps: Ports.deps) => promise<unit> = async (~deps) => {
  let status = if ProbeState.isReady() {
    "{\"status\":\"ready\"}"
  } else {
    "{\"status\":\"not_ready\"}"
  }
  Console.log(status)
  deps.process.exit(0)
}

let routeInit: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  if args->Array.includes("--global") {
    await Commands.runInitGlobal(~deps)
  } else if parseCommandFlag(args, ~name="help") {
    Help.printUsage()
    deps.process.exit(0)
  } else {
    await Commands.runInit(~deps)
  }
}

let routeGenerate: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  if parseCommandFlag(args, ~name="help") {
    Help.printHelpFor("generate")
    deps.process.exit(0)
  }
  let classification = switch args[1] {
  | Some(c) if !String.startsWith(c, "-") => c
  | Some(c) if String.startsWith(c, "-") => {
      Console.error("Error: 'generate' requires a classification argument")
      Help.printUsage()
      deps.process.exit(1)
      ""
    }
  | _ => {
      Console.error("Error: 'generate' requires a classification argument")
      Help.printUsage()
      deps.process.exit(1)
      ""
    }
  }
  let parsedResult = deps.argParser.parse(
    ~args=Array.slice(args, ~start=2),
    ~strict=false,
    ~allowPositionals=true,
  )
  let parsed = switch parsedResult {
  | Ok(p) => p
  | Error(e) => {
      Console.error("CLI argument parse error: " ++ e)
      deps.process.exit(1)
      {Ports.values: Dict.make(), positionals: []}
    }
  }
  let name = switch Dict.get(parsed.values, "name") {
  | Some(n) => n
  | None => classification
  }
  let force = parseCommandFlag(args, ~name="force") || (
    switch Dict.get(parsed.values, "force") {
    | Some("true") => true
    | _ => false
    }
  )
  let outputDir = switch Dict.get(parsed.values, "output") {
  | Some(d) => d
  | None => Config.defaultOutputDir
  }
  let cliAttributes: dict<Context.attrValue> = Dict.make()
  Dict.set(cliAttributes, "name", Context.Scalar(name))
  let flagArgs = Array.slice(args, ~start=2)
  let extracted = extractAttributes(~args=flagArgs)
  extracted->Dict.toArray->Array.forEach(((k, v)) => {
    Dict.set(cliAttributes, k, v)
  })
  let fs = deps.fs
  let pathAdapter = deps.path
  await Commands.runGenerate(
    ~deps, ~fs, ~path=pathAdapter, ~classification, ~name, ~force, ~outputDir, ~cliAttributes,
  )
}

let routeTemplate: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  if parseCommandFlag(args, ~name="help") {
    Help.printHelpFor("template")
    deps.process.exit(0)
  }
  let action = switch args[1] {
  | Some(a) if String.startsWith(a, "-") => {
      Help.printHelpFor("template")
      deps.process.exit(0)
      ""
    }
  | Some(a) => a
  | None => {
      Console.error("Error: 'template' requires an action: copy | list | remove")
      Help.printUsage()
      deps.process.exit(1)
      ""
    }
  }
  let fs = deps.fs
  let pathAdapter = deps.path
  switch action {
  | "copy" => {
      let name = switch args[2] {
      | Some(n) if !String.startsWith(n, "-") => n
      | _ => {
          Console.error("Error: 'template copy' requires a name")
          Help.printUsage()
          deps.process.exit(1)
          ""
        }
      }
      let force = parseCommandFlag(args, ~name="force")
      await Commands.runTemplateCopy(~deps, ~fs, ~path=pathAdapter, ~name, ~force)
    }
  | "list" => await Commands.runTemplateList(~deps, ~fs, ~path=pathAdapter)
  | "remove" => {
      let name = switch args[2] {
      | Some(n) if !String.startsWith(n, "-") => n
      | _ => {
          Console.error("Error: 'template remove' requires a name")
          Help.printUsage()
          deps.process.exit(1)
          ""
        }
      }
      await Commands.runTemplateRemove(~deps, ~fs, ~path=pathAdapter, ~name)
    }
  | _ => {
      Console.error("Error: unknown template action \"" ++ action ++ "\"")
      Help.printUsage()
      deps.process.exit(1)
    }
  }
  deps.process.exit(0)
}

let routeGenerator: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  if parseCommandFlag(args, ~name="help") {
    Help.printHelpFor("generator")
    deps.process.exit(0)
  }
  let subArgs = Array.slice(args, ~start=1)
  await CommandsGenerator.run(~deps, ~args=subArgs)
}

let isKnownHelpCommand = command =>
  switch command {
  | "generate" | "init" | "template" | "generator" | "help" => true
  | _ => false
  }

let routeHelp: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  let cmd = switch args[1] {
  | Some(c) if !String.startsWith(c, "-") => c
  | _ => ""
  }
  if cmd == "" {
    Help.printUsage()
    deps.process.exit(0)
  } else if !isKnownHelpCommand(cmd) {
    Console.error("Unknown command: " ++ cmd)
    deps.process.exit(1)
  } else {
    Help.printHelpFor(cmd)
    deps.process.exit(0)
  }
}

let routeUnknown: (~deps: Ports.deps, ~command: string) => promise<unit> = async (~deps, ~command) => {
  Console.error("Error: unknown command \"" ++ command ++ "\"")
  Help.printUsage()
  deps.process.exit(1)
}

// ─── Main dispatcher ─────────────────────────────────────────────────────────

let route: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  if args[0] == Some("--version") || args[0] == Some("-v") {
    await routeVersion(~deps)
  } else if Array.length(args) == 0 {
    Help.printUsage()
    deps.process.exit(0)
  } else {
    let command = switch args[0] {
    | Some(c) => c
    | None => ""
    }
    switch command {
    | "healthz" => {
        Console.log("{\"status\":\"ok\"}")
        deps.process.exit(0)
      }
    | "readyz" => await routeReadyz(~deps)
    | "init" => await routeInit(~deps, ~args)
    | "generate" => await routeGenerate(~deps, ~args)
    | "template" => await routeTemplate(~deps, ~args)
    | "generator" => await routeGenerator(~deps, ~args)
    | "help" => await routeHelp(~deps, ~args)
    | "--help" | "-h" => {
        Help.printUsage()
        deps.process.exit(0)
      }
    | other => await routeUnknown(~deps, ~command=other)
    }
  }
}
