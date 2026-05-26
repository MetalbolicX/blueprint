let route: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  if Array.length(args) == 0 {
    Help.printUsage()
    deps.process.exit(0)
  } else {
    let fs = deps.fs
    let pathAdapter = deps.path
    let command = switch args[0] {
    | Some(c) => c
    | None => ""
    }

    switch command {
    | "init" => {
        if args->Array.includes("--global") {
          await Commands.runInitGlobal(~deps)
        } else if args->Array.includes("--help") || args->Array.includes("-h") {
          Help.printUsage()
          deps.process.exit(0)
        } else {
          await Commands.runInit(~deps)
        }
      }
    | "generate" => {
        let classification = switch args[1] {
        | Some(c) if !String.startsWith(c, "-") => c
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

        await Commands.runGenerate(
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
            Help.printUsage()
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
              Help.printUsage()
              deps.process.exit(1)
              ""
            }
          }
          let force = args->Array.includes("--force") || args->Array.includes("-f")
          await Commands.runTemplateCopy(~deps, ~fs, ~path=pathAdapter, ~name, ~force)
        | "list" => await Commands.runTemplateList(~deps, ~fs, ~path=pathAdapter)
        | "remove" =>
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
        | _ => {
            Console.error("Error: unknown template action \"" ++ action ++ "\"")
            Help.printUsage()
            deps.process.exit(1)
          }
        }
      }
    | "--help" | "-h" => {
        Help.printUsage()
        deps.process.exit(0)
      }
    | other => {
        Console.error("Error: unknown command \"" ++ other ++ "\"")
        Help.printUsage()
        deps.process.exit(1)
      }
    }
  }
}
