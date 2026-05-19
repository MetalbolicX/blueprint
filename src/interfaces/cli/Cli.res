// Blueprint CLI — init + generate commands

let printUsage = () => {
  Console.log("Usage: blueprint <command> [options]")
  Console.log("")
  Console.log("Commands:")
  Console.log("  init                   Scaffold a .blueprint.yaml config file")
  Console.log("  init --global          Scaffold a global ~/.config/blueprint/config.yaml")
  Console.log("  generate <class>       Run template generation")
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
    let content = "# Global Blueprint configuration\n# Loaded from ~/.config/blueprint/config.yaml\n\ntemplates: []\nallow_dangerous_commands: false\nforce_overwrite: false\ndry_run: false\ntimeout: 5\ndefault_attributes: {}\n"
    let _ = await Bindings.Fs.writeFile(configPath, content)
    Console.log("Scaffolded global config at " ++ configPath)
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

  // Build search paths: project paths first, then global paths
  let projectPaths = ["_templates", "templates", "generators"]
  let allPaths = Array.concat(projectPaths, mergedConfig.templates)
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
          Console.log(
            "Blueprint: generated " ++
            Int.toString(r.filesCreated) +
            " file(s), " ++
            Int.toString(r.commandsExecuted) +
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
