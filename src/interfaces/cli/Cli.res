// Blueprint CLI — init + generate commands

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

let runInitGlobal: unit => promise<unit> = async () => {
  let homeDir = Bindings.Os.homedir()
  let configDir = Bindings.Path.join(Bindings.Path.join(homeDir, ".config"), "blueprint")
  let configPath = Bindings.Path.join(configDir, "config.yaml")

  // Check if global config already exists
  let exists = await Bindings.Fs.fileExists(configPath)
  if exists {
    Console.error("Error: Global config already exists at " ++ configPath)
    NodeJs.NodeProcess.exit(1)
  } else {
    // Create the directory if it doesn't exist
    let dirExists = await Bindings.Fs.fileExists(configDir)
    if !dirExists {
      let _ = await Bindings.Fs.mkdir(configDir, ~options={recursive: true})
    }
    let content = "# Global Blueprint configuration\n# Loaded from ~/.config/blueprint/config.yaml\n\ntemplates: []\nallow_dangerous_commands: false\nforce_overwrite: false\ndry_run: false\ntimeout: 5\ndefault_attributes: {}\nregistry: []\n"
    let _ = await Bindings.Fs.writeFile(configPath, content)
    Console.log("Scaffolded global config at " ++ configPath)
  }
}

let globalTemplateRegistryRoot: unit => string = () => {
  let homeDir = Bindings.Os.homedir()
  Bindings.Path.join(Bindings.Path.join(Bindings.Path.join(homeDir, ".config"), "blueprint"), "templates")
}

let globalConfigPath: unit => string = () => {
  let homeDir = Bindings.Os.homedir()
  Bindings.Path.join(Bindings.Path.join(Bindings.Path.join(homeDir, ".config"), "blueprint"), "config.yaml")
}

let buildGenerateSearchPaths: (
  ~projectPaths: array<string>,
  ~registry: array<Config.templateSource>,
  ~globalTemplates: array<string>,
) => array<string> = (~projectPaths, ~registry, ~globalTemplates) => {
  let registryPaths = registry
  ->Array.map(src => Bindings.Path.dirname(src.path))
  ->Array.reduce([], (acc, path) =>
    if acc->Array.includes(path) {
      acc
    } else {
      acc->Array.concat([path])
    }
  )
  projectPaths->Array.concat(registryPaths)->Array.concat(globalTemplates)
}

let promptOverwrite: string => promise<bool> = targetPath => {
  let rl = Bindings.Readline.createInterface(~input=Bindings.Readline.stdin, ~output=Bindings.Readline.stdout, ())
  rl.question("Template already exists at " ++ targetPath ++ ". Overwrite? (y/n) ")
  ->Promise.then(answer => {
    rl.close()
    let trimmed = String.trim(answer)->String.toLowerCase
    Promise.resolve(trimmed == "y" || trimmed == "yes")
  })
}

let copyTemplateToRegistry: (
  ~name: string,
  ~sourcePath: string,
  ~registryRoot: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
  ~force: bool,
  ~confirmOverwrite: string => promise<bool>,
) => promise<result<Config.globalConfig, string>> = async (
  ~name,
  ~sourcePath,
  ~registryRoot,
  ~configPath,
  ~globalConfig,
  ~force,
  ~confirmOverwrite,
) => {
  try {
    let sourceAbs = if Bindings.Path.isAbsolute(sourcePath) {
      sourcePath
    } else {
      Bindings.Path.resolve(NodeJs.NodeProcess.cwd(), sourcePath)
    }
    let targetPath = Bindings.Path.join(registryRoot, name)
    let targetExists = await Bindings.Fs.fileExists(targetPath)

    if targetExists && !force {
      let shouldOverwrite = await confirmOverwrite(targetPath)
      if !shouldOverwrite {
        Error("Copy cancelled by user")
      } else {
        let _ = await Bindings.Fs.rm(targetPath, ~options={recursive: true})
        let _ = await Bindings.Fs.mkdir(registryRoot, ~options={recursive: true})
        let _ = await Bindings.Fs.cp(sourceAbs, targetPath, ~options={recursive: true})

        let withoutCurrent = globalConfig.registry->Array.filter(entry => entry.name != name)
        let updated: Config.globalConfig = {
          ...globalConfig,
          registry: withoutCurrent->Array.concat([{name, source: sourceAbs, path: targetPath}]),
        }
        let saveResult = await Config.saveGlobalAtPath(~configPath, updated)
        switch saveResult {
        | Ok(()) => Ok(updated)
        | Error(e) => Error(e)
        }
      }
    } else {
      if targetExists {
        let _ = await Bindings.Fs.rm(targetPath, ~options={recursive: true})
      }
      let _ = await Bindings.Fs.mkdir(registryRoot, ~options={recursive: true})
      let _ = await Bindings.Fs.cp(sourceAbs, targetPath, ~options={recursive: true})

      let withoutCurrent = globalConfig.registry->Array.filter(entry => entry.name != name)
      let updated: Config.globalConfig = {
        ...globalConfig,
        registry: withoutCurrent->Array.concat([{name, source: sourceAbs, path: targetPath}]),
      }
      let saveResult = await Config.saveGlobalAtPath(~configPath, updated)
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

let removeTemplateFromRegistry: (
  ~name: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
) => promise<result<Config.globalConfig, string>> = async (~name, ~configPath, ~globalConfig) => {
  let toRemove = globalConfig.registry->Array.find(entry => entry.name == name)
  switch toRemove {
  | None => Error("Template not found: " ++ name)
  | Some(entry) =>
    try {
      let exists = await Bindings.Fs.fileExists(entry.path)
      if exists {
        let _ = await Bindings.Fs.rm(entry.path, ~options={recursive: true})
      }
      let updated: Config.globalConfig = {
        ...globalConfig,
        registry: globalConfig.registry->Array.filter(src => src.name != name),
      }
      let saveResult = await Config.saveGlobalAtPath(~configPath, updated)
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

let runTemplateCopy: (~name: string, ~force: bool) => promise<unit> = async (~name, ~force) => {
  let globalConfigResult = await Config.loadGlobal()
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig
  }

  let cwd = NodeJs.NodeProcess.cwd()
  let configResult = await Config.loadFrom(cwd)
  let projectConfig = switch configResult {
  | Ok(c) => c
  | Error(_) => None
  }
  let merged = Config.mergeConfig(~global=globalConfig, ~project=projectConfig)
  let sourceSearchPaths = ["_templates", "templates", "generators"]->Array.concat(merged.templates)
  let generators = await Discovery.discover(~searchPaths=sourceSearchPaths, ())

  switch Discovery.findByClassification(generators, name) {
  | None => {
      Console.error("Error: template not found: " ++ name)
      NodeJs.NodeProcess.exit(1)
    }
  | Some(generator) => {
      let registryRoot = globalTemplateRegistryRoot()
      let configPath = globalConfigPath()
      let result = await copyTemplateToRegistry(
        ~name,
        ~sourcePath=generator.path,
        ~registryRoot,
        ~configPath,
        ~globalConfig,
        ~force,
        ~confirmOverwrite=promptOverwrite,
      )
      switch result {
      | Ok(_) => Console.log("Installed template: " ++ name ++ " -> " ++ Bindings.Path.join(registryRoot, name))
      | Error(e) => {
          Console.error("Error: " ++ e)
          NodeJs.NodeProcess.exit(1)
        }
      }
    }
  }
}

let runTemplateList: unit => promise<unit> = async () => {
  let globalConfigResult = await Config.loadGlobal()
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

let runTemplateRemove: (~name: string) => promise<unit> = async (~name) => {
  let globalConfigResult = await Config.loadGlobal()
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig
  }
  let configPath = globalConfigPath()
  let result = await removeTemplateFromRegistry(~name, ~configPath, ~globalConfig)
  switch result {
  | Ok(_) => Console.log("Removed template: " ++ name)
  | Error(e) => {
      Console.error("Error: " ++ e)
      NodeJs.NodeProcess.exit(1)
    }
  }
}

let runInit: unit => promise<unit> = async () => {
  let cwd = NodeJs.NodeProcess.cwd()
  let configPath = Bindings.Path.join(cwd, ".blueprint.yaml")

  let exists = await Bindings.Fs.fileExists(configPath)
  if exists {
    Console.error("Error: .blueprint.yaml already exists at " ++ configPath)
    NodeJs.NodeProcess.exit(1)
  } else {
    let content = "# Blueprint configuration\ngenerators: []\nhooks:\n  pre_generate: \"\"\n  post_generate: \"\"\n  timeout: 5s\n"
    await Bindings.Fs.writeFile(configPath, content)
    Console.log("Scaffolded .blueprint.yaml at " ++ configPath)
  }
}

let runGenerate: (
  ~classification: string,
  ~name: string,
  ~force: bool,
  ~outputDir: string,
  ~cliAttributes: dict<string>,
) => promise<unit> = async (~classification, ~name, ~force, ~outputDir, ~cliAttributes) => {
  // Load global config (from ~/.config/blueprint/config.yaml)
  let globalConfigResult = await Config.loadGlobal()
  let globalConfig = switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => Config.defaultGlobalConfig
  | Error(_) => Config.defaultGlobalConfig // fallback silently
  }

  let cwd = NodeJs.NodeProcess.cwd()
  let configResult = await Config.loadFrom(cwd)
  let projectConfig = switch configResult {
  | Ok(c) => c
  | Error(e) => {
      Console.error("Error loading .blueprint.yaml: " ++ e)
      NodeJs.NodeProcess.exit(1)
      None
    }
  }

  let mergedConfig = Config.mergeConfig(~global=globalConfig, ~project=projectConfig)

  // Build search paths: project paths first, then registry paths, then raw global paths
  let projectPaths = ["_templates", "templates", "generators"]
  let allPaths = buildGenerateSearchPaths(
    ~projectPaths,
    ~registry=globalConfig.registry,
    ~globalTemplates=mergedConfig.templates,
  )
  let generators = await Discovery.discover(~searchPaths=allPaths, ())

  switch Discovery.findByClassification(generators, classification) {
  | None => {
      Console.error("Error: generator not found for classification \"" ++ classification ++ "\"")
      NodeJs.NodeProcess.exit(1)
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
      )

      switch result {
      | Error(e) => {
          Console.error("Error: " ++ e)
          NodeJs.NodeProcess.exit(1)
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
  let argv = NodeJs.NodeProcess.argv

  // argv[0] = node, argv[1] = script path, argv[2+] = actual args
  let args = Array.slice(argv, ~start=2)

  if Array.length(args) == 0 {
    printUsage()
    NodeJs.NodeProcess.exit(0)
  } else {
    let command = switch args[0] {
    | Some(c) => c
    | None => ""
    }

    switch command {
    | "init" => {
        // Check for --global flag or --help/-h
        if args->Array.includes("--global") {
          await runInitGlobal()
        } else if args->Array.includes("--help") || args->Array.includes("-h") {
          printUsage()
          NodeJs.NodeProcess.exit(0)
        } else {
          await runInit()
        }
      }

    | "generate" => {
        let classification = switch args[1] {
        | Some(c) if !String.startsWith(c, "-") => c
        | _ => {
            Console.error("Error: 'generate' requires a classification argument")
            printUsage()
            NodeJs.NodeProcess.exit(1)
            ""
          }
        }

        let options: dict<Bindings.Util.flagConfig> = Dict.make()
        Dict.set(options, "name", {Bindings.Util.type_: "string"})
        Dict.set(options, "force", {Bindings.Util.type_: "boolean"})
        Dict.set(options, "output", {Bindings.Util.type_: "string"})

        let parsed = Bindings.ParseArgs.parseArgs({
          args: Array.slice(args, ~start=2),
          options,
          strict: false,
          allowPositionals: true,
        })

        let name = switch parsed.values.name {
        | Some(n) => n
        | None => classification
        }

        // NOTE: parseArgs binding doesn't support custom boolean flags in values.
        // Force is checked from positionals as a workaround.
        let force = args->Array.includes("--force") || args->Array.includes("-f")

        let outputDir = switch parsed.values.output {
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
            NodeJs.NodeProcess.exit(1)
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
              NodeJs.NodeProcess.exit(1)
              ""
            }
          }
          let force = args->Array.includes("--force") || args->Array.includes("-f")
          await runTemplateCopy(~name, ~force)
        | "list" => await runTemplateList()
        | "remove" =>
          let name = switch args[2] {
          | Some(n) if !String.startsWith(n, "-") => n
          | _ => {
              Console.error("Error: 'template remove' requires a name")
              printUsage()
              NodeJs.NodeProcess.exit(1)
              ""
            }
          }
          await runTemplateRemove(~name)
        | _ => {
            Console.error("Error: unknown template action \"" ++ action ++ "\"")
            printUsage()
            NodeJs.NodeProcess.exit(1)
          }
        }
      }

    | "--help" | "-h" => {
        printUsage()
        NodeJs.NodeProcess.exit(0)
      }

    | other => {
        Console.error("Error: unknown command \"" ++ other ++ "\"")
        printUsage()
        NodeJs.NodeProcess.exit(1)
      }
    }
  }
}
