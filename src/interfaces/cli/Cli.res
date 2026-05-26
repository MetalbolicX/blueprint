// Blueprint CLI — init + generate commands

@warning("-33")
open NodeJsFileSystem
@warning("-33")
open NodeJsPath
@warning("-33")
open NodeJsProcess
@warning("-33")
open NodeJsShell

let printUsage = () => {
  Console.log("Usage: blueprint <command> [options]")
  Console.log("")
  Console.log("Commands:")
  Console.log("  init                   Scaffold a .blueprint.yaml config file")
  Console.log("  init --global          Scaffold a global ~/.config/blueprint/config.yaml")
  Console.log("  generate <class>       Run template generation")
  Console.log("  template copy <name>   Copy a generator into global template registry")
  Console.log("  template list          List globally installed templates")
  Console.log("  template remove <name> Remove a globally installed template")
  Console.log("")
  Console.log("Options (generate):")
  Console.log("  --name <name>          Component name")
  Console.log("  --force                Skip prompts, overwrite files")
  Console.log("  --output <dir>         Output directory (default: generated)")
  Console.log("  --<key> <value>        Arbitrary attributes passed to templates")
}

let runInitGlobal: (~deps: Ports.deps) => promise<unit> = async (~deps) => {
  let homeDir = Bindings.Os.homedir()
  let configDir = deps.path.join(deps.path.join(homeDir, ".config"), "blueprint")
  let configPath = deps.path.join(configDir, "config.yaml")

  // Check if global config already exists
  let exists = await deps.fs.fileExists(configPath)
  if exists {
    Console.error("Error: Global config already exists at " ++ configPath)
    deps.process.exit(1)
  } else {
    // Create the directory if it doesn't exist
    let dirExists = await deps.fs.fileExists(configDir)
    if !dirExists {
      let _ = await deps.fs.mkdir(configDir, ~options={recursive: true})
    }
    let content = "# Global Blueprint configuration\n# Loaded from ~/.config/blueprint/config.yaml\n\ntemplates: []\nallow_dangerous_commands: false\nforce_overwrite: false\ndry_run: false\ntimeout: 5\ndefault_attributes: {}\nregistry: []\n"
    let _ = await deps.fs.writeFile(configPath, content)
    Console.log("Scaffolded global config at " ++ configPath)
  }
}

let globalTemplateRegistryRoot: (~deps: Ports.deps) => string = (~deps) => {
  let homeDir = Bindings.Os.homedir()
  deps.path.join(deps.path.join(deps.path.join(homeDir, ".config"), "blueprint"), "templates")
}

let globalConfigPath: (~deps: Ports.deps) => string = (~deps) => {
  let homeDir = Bindings.Os.homedir()
  deps.path.join(deps.path.join(deps.path.join(homeDir, ".config"), "blueprint"), "config.yaml")
}

let buildGenerateSearchPaths: (
  ~deps: Ports.deps,
  ~projectPaths: array<string>,
  ~registry: array<Config.templateSource>,
  ~globalTemplates: array<string>,
) => array<string> = (~deps: Ports.deps, ~projectPaths, ~registry, ~globalTemplates) => {
  let registryPaths = registry
  ->Array.map(src => deps.path.dirname(src.path))
  ->Array.reduce([], (acc, path) =>
    if acc->Array.includes(path) {
      acc
    } else {
      acc->Array.concat([path])
    }
  )
  projectPaths->Array.concat(registryPaths)->Array.concat(globalTemplates)
}

let copyTemplateToRegistry: (~deps: Ports.deps, 
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~sourcePath: string,
  ~registryRoot: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
  ~force: bool,
  ~confirmOverwrite: string => promise<bool>,
) => promise<result<Config.globalConfig, string>> = async (~deps, 
  ~fs,
  ~path,
  ~name,
  ~sourcePath,
  ~registryRoot,
  ~configPath,
  ~globalConfig,
  ~force,
  ~confirmOverwrite,
) => {
  try {
    let sourceAbs = if deps.path.isAbsolute(sourcePath) {
      sourcePath
    } else {
      deps.path.resolve(deps.process.cwd(), sourcePath)
    }
    let targetPath = deps.path.join(registryRoot, name)
    let targetExists = await deps.fs.fileExists(targetPath)

    if targetExists && !force {
      let shouldOverwrite = await confirmOverwrite(targetPath)
      if !shouldOverwrite {
        Error("Copy cancelled by user")
      } else {
        let _ = await deps.fs.rm(targetPath, ~options={recursive: true})
        let _ = await deps.fs.mkdir(registryRoot, ~options={recursive: true})
        let _ = await deps.fs.cp(sourceAbs, targetPath, ~options={recursive: true})

        let withoutCurrent = globalConfig.registry->Array.filter(entry => entry.name != name)
        let updated: Config.globalConfig = {
          ...globalConfig,
          registry: withoutCurrent->Array.concat([{name, source: sourceAbs, path: targetPath}]),
        }
        let saveResult = await Config.saveGlobalAtPath(~fs, ~path, ~configPath, updated)
        switch saveResult {
        | Ok(()) => Ok(updated)
        | Error(e) => Error(e)
        }
      }
    } else {
      if targetExists {
        let _ = await deps.fs.rm(targetPath, ~options={recursive: true})
      }
      let _ = await deps.fs.mkdir(registryRoot, ~options={recursive: true})
      let _ = await deps.fs.cp(sourceAbs, targetPath, ~options={recursive: true})

      let withoutCurrent = globalConfig.registry->Array.filter(entry => entry.name != name)
      let updated: Config.globalConfig = {
        ...globalConfig,
        registry: withoutCurrent->Array.concat([{name, source: sourceAbs, path: targetPath}]),
      }
      let saveResult = await Config.saveGlobalAtPath(~fs, ~path, ~configPath, updated)
      switch saveResult {
      | Ok(()) => Ok(updated)
      | Error(e) => Error(e)
      }
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to copy template"
    }
    Error(msg)
  }
}

let removeTemplateFromRegistry: (~deps: Ports.deps, 
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
) => promise<result<Config.globalConfig, string>> = async (~deps, ~fs, ~path, ~name, ~configPath, ~globalConfig) => {
  let toRemove = globalConfig.registry->Array.find(entry => entry.name == name)
  switch toRemove {
  | None => Error("Template not found: " ++ name)
  | Some(entry) =>
    try {
      let exists = await deps.fs.fileExists(entry.path)
      if exists {
        let _ = await deps.fs.rm(entry.path, ~options={recursive: true})
      }
      let updated: Config.globalConfig = {
        ...globalConfig,
        registry: globalConfig.registry->Array.filter(src => src.name != name),
      }
      let saveResult = await Config.saveGlobalAtPath(~fs, ~path, ~configPath, updated)
      switch saveResult {
      | Ok(()) => Ok(updated)
      | Error(e) => Error(e)
      }
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Failed to remove template"
      }
      Error(msg)
    }
  }
}

let runTemplateCopy: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~force: bool,
) => promise<unit> = async (~deps, ~fs, ~path, ~name, ~force) => {
  let homeDir = Bindings.Os.homedir()
  let globalConfigResult = await Config.loadGlobal(~fs, ~path, ~homeDir)
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig
  }

  let cwd = deps.process.cwd()
  let configResult = await Config.loadFrom(~fs, ~path, cwd)
  let projectConfig = switch configResult {
  | Ok(c) => c
  | Error(_) => None
  }
  let merged = Config.mergeConfig(~global=globalConfig, ~project=projectConfig)
  let sourceSearchPaths = ["_templates", "templates", "generators"]->Array.concat(merged.templates)
  let generators = await Discovery.discover(~fs, ~path, ~searchPaths=sourceSearchPaths, ())

  switch Discovery.findByClassification(generators, name) {
  | None => {
      Console.error("Error: template not found: " ++ name)
      deps.process.exit(1)
    }
  | Some(generator) => {
      let registryRoot = globalTemplateRegistryRoot(~deps)
      let configPath = globalConfigPath(~deps)
      let result = await copyTemplateToRegistry(~deps, 
        ~fs,
        ~path,
        ~name,
        ~sourcePath=generator.path,
        ~registryRoot,
        ~configPath,
        ~globalConfig,
        ~force,
        ~confirmOverwrite=targetPath => deps.interactiveIO.askConfirm(~question="Template already exists at " ++ targetPath ++ ". Overwrite?", ~defaultYes=false),
      )
      switch result {
      | Ok(_) => Console.log("Installed template: " ++ name ++ " -> " ++ deps.path.join(registryRoot, name))
      | Error(e) => {
          Console.error("Error: " ++ e)
          deps.process.exit(1)
        }
      }
    }
  }
}

let runTemplateList: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<unit> = async (~deps, ~fs, ~path) => {
  let _ = deps
  let homeDir = Bindings.Os.homedir()
  let globalConfigResult = await Config.loadGlobal(~fs, ~path, ~homeDir)
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig
  }

  if Array.length(globalConfig.registry) == 0 {
    Console.log("No templates installed in registry.")
  } else {
    globalConfig.registry
    ->Array.forEach(entry => Console.log(entry.name ++ "\t" ++ entry.source ++ "\t" ++ entry.path))
  }
}

let runTemplateRemove: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
) => promise<unit> = async (~deps, ~fs, ~path, ~name) => {
  let homeDir = Bindings.Os.homedir()
  let globalConfigResult = await Config.loadGlobal(~fs, ~path, ~homeDir)
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig
  }
  let configPath = globalConfigPath(~deps)
  let result = await removeTemplateFromRegistry(~deps, ~fs, ~path, ~name, ~configPath, ~globalConfig)
  switch result {
  | Ok(_) => Console.log("Removed template: " ++ name)
  | Error(e) => {
      Console.error("Error: " ++ e)
      deps.process.exit(1)
    }
  }
}

let runInit: (~deps: Ports.deps) => promise<unit> = async (~deps) => {
  let cwd = deps.process.cwd()
  let configPath = deps.path.join(cwd, ".blueprint.yaml")

  let exists = await deps.fs.fileExists(configPath)
  if exists {
    Console.error("Error: .blueprint.yaml already exists at " ++ configPath)
    deps.process.exit(1)
  } else {
    let content = "# Blueprint configuration\n# Generated by Blueprint\n\ngenerators: []\nhooks:\n  pre_generate: \"\"\n  post_generate: \"\"\n  timeout: 5s"
    await deps.fs.writeFile(configPath, content)
    Console.log("Scaffolded .blueprint.yaml at " ++ configPath)
  }
}

let runGenerate: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~deps: Ports.deps,
  ~classification: string,
  ~name: string,
  ~force: bool,
  ~outputDir: string,
  ~cliAttributes: dict<string>,
) => promise<unit> = async (~fs, ~path, ~deps, ~classification, ~name, ~force, ~outputDir, ~cliAttributes) => {
  // Load global config (from ~/.config/blueprint/config.yaml)
  let homeDir = Bindings.Os.homedir()
  let globalConfigResult = await Config.loadGlobal(~fs, ~path, ~homeDir)
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig
  }

  let cwd = deps.process.cwd()
  let configResult = await Config.loadFrom(~fs, ~path, cwd)
  let projectConfig = switch configResult {
  | Ok(c) => c
  | Error(e) => {
      Console.error("Error loading .blueprint.yaml: " ++ e)
      deps.process.exit(1)
      None
    }
  }

  let mergedConfig = Config.mergeConfig(~global=globalConfig, ~project=projectConfig)

  // Build search paths: project paths first, then registry paths, then raw global paths
  let projectPaths = ["_templates", "templates", "generators"]
  let allPaths = buildGenerateSearchPaths(~deps, 
    ~projectPaths,
    ~registry=globalConfig.registry,
    ~globalTemplates=mergedConfig.templates,
  )
  let generators = await Discovery.discover(~fs, ~path, ~searchPaths=allPaths, ())

  switch Discovery.findByClassification(generators, classification) {
  | None => {
      Console.error("Error: generator not found for classification \"" ++ classification ++ "\"")
      deps.process.exit(1)
    }
  | Some(generator) => {
      // Build effective config for Engine (using merged timeout)
      // Keep project hooks as-is but use merged timeout
      let effectiveConfig: Config.config = {
        output: ?projectConfig->Option.flatMap(c => c.output),
        hooks: ?Some({
          preGenerate: ?projectConfig->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.preGenerate),
          postGenerate: ?projectConfig->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.postGenerate),
          timeout: mergedConfig.timeout,
        }),
        shell: ?mergedConfig.shell,
      }

      let result = await Engine.run(
        ~generator,
        ~name,
        ~cliAttributes,
        ~outputDir,
        ~force,
        ~config=effectiveConfig,
        ~deps,
      )

      switch result {
      | Error(e) => {
          Console.error("Error: " ++ e)
          deps.process.exit(1)
        }
      | Ok(r) => {
          switch r.shellErrors {
          | Some(errs) if errs->Array.length > 0 =>
            errs->Array.forEach(err => Console.warn("Shell warning: " ++ err))
          | _ => ()
          }
          Console.log(
            "Blueprint: generated " ++
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

let main: unit => promise<unit> = async () => {
  // Build port adapters dynamically based on runtime
  let deps: Ports.deps = if Runtime.isDeno() {
    {
      fs: DenoFileSystem.make(),
      path: DenoPath.make(),
      process: DenoProcess.make(),
      shell: DenoShell.make(),
      interactiveIO: DenoInteractiveIO.make(()),
      argParser: DenoArgParser.make(),
    }
  } else {
    {
      fs: NodeJsFileSystem.make(),
      path: NodeJsPath.make(),
      process: NodeJsProcess.make(),
      shell: NodeJsShell.make(),
      interactiveIO: NodeJsInteractiveIO.make(()),
      argParser: NodeJsArgParser.make(),
    }
  }

  let fs = deps.fs
  let pathAdapter = deps.path
  let processAdapter = deps.process
  let argv = processAdapter.argv()

  // argv[0] = node, argv[1] = script path, argv[2+] = actual args
  let args = Array.slice(argv, ~start=2)

  if Array.length(args) == 0 {
    printUsage()
    deps.process.exit(0)
  } else {
    let command = switch args[0] {
    | Some(c) => c
    | None => ""
    }

    switch command {
    | "init" => {
        // Check for --global flag or --help/-h
        if args->Array.includes("--global") {
          await runInitGlobal(~deps)
        } else if args->Array.includes("--help") || args->Array.includes("-h") {
          printUsage()
          deps.process.exit(0)
        } else {
          await runInit(~deps)
        }
      }

    | "generate" => {
        let classification = switch args[1] {
        | Some(c) if !String.startsWith(c, "-") => c
        | _ => {
            Console.error("Error: 'generate' requires a classification argument")
            printUsage()
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
            {Ports.values: Dict.make(), positionals: []} // Unreachable
          }
        }

        let name = switch Dict.get(parsed.values, "name") {
        | Some(n) => n
        | None => classification
        }

        // NOTE: parseArgs binding doesn't support custom boolean flags in values.
        // Force is checked from positionals as a workaround.
        let force = args->Array.includes("--force") || args->Array.includes("-f") || (
          switch Dict.get(parsed.values, "force") {
          | Some("true") => true
          | _ => false
          }
        )

        let outputDir = switch Dict.get(parsed.values, "output") {
        | Some(d) => d
        | None => Config.defaultOutputDir
        }

        let cliAttributes = Dict.make()
        Dict.set(cliAttributes, "name", name)

        // Scan remaining args for arbitrary --key value pairs
        let flagArgs = Array.slice(args, ~start=2)
        let len = Array.length(flagArgs)
        let i = ref(0)
        while i.contents < len {
          let arg = Array.getUnsafe(flagArgs, i.contents)
          if String.startsWith(arg, "--") {
            let eqIdx = String.indexOf(arg, "=")
            let key = if eqIdx >= 0 {
              String.slice(arg, ~start=2, ~end=eqIdx)
            } else {
              String.slice(arg, ~start=2)
            }
            if key != "name" && key != "force" && key != "output" {
              let value = if eqIdx >= 0 {
                String.slice(arg, ~start=eqIdx + 1)
              } else if i.contents + 1 < len && !String.startsWith(Array.getUnsafe(flagArgs, i.contents + 1), "-") {
                i := i.contents + 1
                Array.getUnsafe(flagArgs, i.contents)
              } else {
                "true"
              }
              Dict.set(cliAttributes, key, value)
            }
          }
          i := i.contents + 1
        }

        await runGenerate(
          ~fs,
          ~path=pathAdapter,
          ~deps,
          ~classification,
          ~name,
          ~force,
          ~outputDir,
          ~cliAttributes,
        )
      }

    | "template" => {
        let action = switch args[1] {
        | Some(a) => a
        | None => {
            Console.error("Error: 'template' requires an action: copy | list | remove")
            printUsage()
            deps.process.exit(1)
            ""
          }
        }

        switch action {
        | "copy" =>
          let name = switch args[2] {
          | Some(n) if !String.startsWith(n, "-") => n
          | _ => {
              Console.error("Error: 'template copy' requires a name")
              printUsage()
              deps.process.exit(1)
              ""
            }
          }
          let force = args->Array.includes("--force") || args->Array.includes("-f")
          await runTemplateCopy(~deps, ~fs, ~path=pathAdapter, ~name, ~force)
        | "list" => await runTemplateList(~deps, ~fs, ~path=pathAdapter)
        | "remove" =>
          let name = switch args[2] {
          | Some(n) if !String.startsWith(n, "-") => n
          | _ => {
              Console.error("Error: 'template remove' requires a name")
              printUsage()
              deps.process.exit(1)
              ""
            }
          }
          await runTemplateRemove(~deps, ~fs, ~path=pathAdapter, ~name)
        | _ => {
            Console.error("Error: unknown template action \"" ++ action ++ "\"")
            printUsage()
            deps.process.exit(1)
          }
        }
      }

    | "--help" | "-h" => {
        printUsage()
        deps.process.exit(0)
      }

    | other => {
        Console.error("Error: unknown command \"" ++ other ++ "\"")
        printUsage()
        deps.process.exit(1)
      }
    }
  }
}
