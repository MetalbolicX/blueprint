// Cli — CLI entry point using node:util parseArgs
// Commands: fluxo init, fluxo generate <classification>

module Args = Bindings.ParseArgs

type command =
  | Init
  | Generate(string)  // classification arg
  | Help

// Parse CLI arguments into command
let parseArgs: array<string> => command = args => {
  let config = {
    args: Some(args),
    options: Some(Js.Dict.fromArray([
      ("name", Args.parseOptions(~short="n", ~default=Js.Json.JNull, ())),
      ("force", Args.parseOptions(~short="f", ~default=Js.Json.JFalse, ())),
      ("output", Args.parseOptions(~short="o", ~default=Js.Json.JNull, ())),
    ])),
    strict: false,
    allowPositionals: true,
  }

  let parsed = Args.parseArgs(config)
  let values = parsed.values

  // Get positionals
  let pos = parsed.positionals
  let cmd = switch Js.Array.length(pos) {
  | 0 => Help
  | _ => {
      let first = pos[0]
      switch first {
      | "init" => Init
      | "generate" if Js.Array.length(pos) >= 2 => Generate(pos[1])
      | "help" | "-h" | "--help" => Help
      | _ => Help
      }
    }
  }
}

// Get named option as string
let getStringOpt: (Bindings.ParseArgs.parsedValues, string) => option<string> = (values, key) => {
  Args.getString(values, key)
}

// Get named option as bool
let getBoolOpt: (Bindings.ParseArgs.parsedValues, string) => bool = (values, key) => {
  Args.getBool(values, key)
}

// Get name argument
let getName: Bindings.ParseArgs.parsedValues => option<string> = values => {
  getStringOpt(values, "name")
}

// Get force flag
let getForce: Bindings.ParseArgs.parsedValues => bool = values => {
  getBoolOpt(values, "force")
}

// Get output directory
let getOutput: Bindings.ParseArgs.parsedValues => option<string> = values => {
  getStringOpt(values, "output")
}

// Print usage
let printUsage: unit => unit = () => {
  Js.Console.log("Fluxo - Transactional code generator
Usage: fluxo <command> [options]

Commands:
  fluxo init                          Scaffold .fluxo.yaml in current directory
  fluxo generate <classification>    Run template generator

Options:
  -n, --name <name>      Component name
  -f, --force            Skip prompts, overwrite existing files
  -o, --output <dir>     Output directory (default: generated)
  -h, --help             Show this help message")
}

// Handle init command — write default .fluxo.yaml
let handleInit: unit => promise<unit> = async () => {
  let configPath = Node.Path.join(Node.Process.cwd(), ".fluxo.yaml")
  let exists = await Bindings.Fs.fileExists(configPath)

  if exists {
    Js.Console.log(".fluxo.yaml already exists")
  } else {
    let defaultConfig = "hooks:\n  # pre_generate: echo 'before generation'\n  # post_generate: echo 'after generation'\n  # timeout: 5\n\noutput: generated\n"

    try {
      await Bindings.Fs.writeFile(configPath, defaultConfig, ~options={encoding: "utf8"})
      Js.Console.log("Created .fluxo.yaml")
    } catch {
    | Js.Exn.Error(obj) =>
      let msg = switch Js.Exn.message(obj) {
      | Some(m) => m
      | None => "Unknown error"
      }
      Js.Console.error("Failed to write .fluxo.yaml: " ++ msg)
    }
  }
}

// Handle generate command
let handleGenerate: (string, Bindings.ParseArgs.parsedValues) => promise<unit> = async (classification, values) => {
  let name = getName(values)
  let force = getForce(values)
  let output = getOutput(values)

  if name == None {
    Js.Console.error("Error: --name is required. Use -n <name> or --name <name>")
    Node.Process.exit(1)
  }

  // Build CLI attributes from remaining options
  let cliAttributes = Js.Dict.empty()
  values->Js.Dict.entries->Js.Array.forEach(((k, v)) => {
    if k != "name" && k != "force" && k != "output" {
      switch Js.Json.classify(v) {
      | Js.Json.JString(s) => Js.Dict.set(cliAttributes, k, s)
      | _ => ()
      }
    }
  })

  // Discover generators
  let generators = await Discovery.discover()

  // Find matching generator
  let generator = generators->Discovery.findByClassification(classification)
  switch generator {
  | Some(gen) => {
      let result = await Engine.runWithConfig(
        ~generator=gen,
        ~name=name->Option.getExn,
        ~cliAttributes,
        ~force,
      )

      switch result {
      | Ok(r) => {
          Js.Console.log("\nGenerated " ++ Js.Int.toString(r.filesCreated) ++ " file(s) for '" ++ r.classification ++ "'")
        }
      | Error(e) => {
          Js.Console.error("Error: " ++ e)
          Node.Process.exit(1)
        }
      }
    }
  | None => {
      Js.Console.error("Generator '" ++ classification ++ "' not found. Available generators:")
      generators->Js.Array.forEach(g => {
        Js.Console.log("  - " ++ g.name)
      })
      Node.Process.exit(1)
    }
  }
}

// Main entry point
let main: unit = () => {
  let args = Node.Process.argv->Js.Array.sliceFrom(2)

  if Js.Array.length(args) == 0 {
    printUsage()
    Node.Process.exit(0)
  }

  let cmd = parseArgs(args)

  switch cmd {
  | Init =>
    handleInit()->Promise.then(_ => Promise.resolve())->ignore

  | Generate(classification) =>
    let values = parseArgs(args).values
    handleGenerate(classification, values)->Promise.then(_ => Promise.resolve())->ignore

  | Help =>
    printUsage()
    Node.Process.exit(0)
  }
}