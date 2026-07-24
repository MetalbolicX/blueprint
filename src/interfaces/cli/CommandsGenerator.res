let projectGeneratorSearchPaths = ["_templates", "templates", "generators"]

let normalizeTemplateFilename = (filename: string) => {
  if String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl") {
    filename
  } else {
    filename ++ ".ejs.t"
  }
}

let normalizeDirectiveKey = (raw: string) => {
  switch raw->String.trim->String.toLowerCase {
  | "atline" | "at_line" => "at_line"
  | "skipif" | "skip_if" => "skip_if"
  | "eoflast" | "eof_last" => "eof_last"
  | "unlessexists" | "unless_exists" => "unless_exists"
  | key => key
  }
}

let parseDirectiveSelection = (selection: string) => {
  selection
  ->String.split(",")
  ->Array.map(normalizeDirectiveKey)
  ->Array.filter(key => key != "")
}

let hasDirective = (~selected: array<string>, ~key: string) => {
  selected->Array.includes(key)
}

let maybeString = (value: string): option<string> => {
  let trimmed = value->String.trim
  trimmed == "" ? None : Some(trimmed)
}

let parsePromptOptions = (raw: string): option<array<Manifest.promptOption>> => {
  let entries =
    raw
    ->String.split(",")
    ->Array.map(s => s->String.trim)
    ->Array.filter(s => s != "")

  if Array.length(entries) == 0 {
    None
  } else {
    Some(entries->Array.map(entry => {
      let sepIndex = String.indexOf(entry, ":")
      if sepIndex >= 0 {
        let label = String.slice(entry, ~start=0, ~end=sepIndex)->String.trim
        let value = String.slice(entry, ~start=sepIndex + 1)->String.trim
        {
          Manifest.label: label == "" ? value : label,
          value,
        }
      } else {
        {Manifest.label: entry, value: entry}
      }
    }))
  }
}

let parsePromptValidation = (pattern: string, message: string): option<Manifest.promptValidation> => {
  switch maybeString(pattern) {
  | Some(p) => Some({pattern: p, message: message->String.trim == "" ? "Invalid value" : message->String.trim})
  | None => None
  }
}

let resolveGeneratorDir: (~deps: Ports.deps, ~name: string) => promise<option<string>> = async (~deps, ~name) => {
  let cwd = deps.process.cwd()
  let possiblePaths = projectGeneratorSearchPaths->Array.map(base => deps.path.join(deps.path.join(cwd, base), name))

  let existing =
    await Promise.all(possiblePaths->Array.map(async candidate => {
      if await deps.fs.fileExists(candidate) {
        let stat = await deps.fs.stat(candidate)
        stat.isDirectory() ? Some(candidate) : None
      } else {
        None
      }
    }))

  existing->Array.findMap(x => x)
}

let requireGeneratorName = (~deps: Ports.deps, ~name: option<string>): option<string> => {
  switch name {
  | Some(n) => Some(n)
  | None => {
      Console.error("Error: generator name is required")
      Help.printHelpFor("generator")
      deps.process.exit(1)
      None
    }
  }
}

let runList: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
  switch requireGeneratorName(~deps, ~name) {
  | None => ()
  | Some(generatorName) => {
      switch await resolveGeneratorDir(~deps, ~name=generatorName) {
      | None => {
          Console.error("Error: generator not found: " ++ generatorName)
          deps.process.exit(1)
        }
      | Some(generatorDir) => {
          let manifestPath = deps.path.join(generatorDir, "manifest.yaml")
          let manifestResult = if await deps.fs.fileExists(manifestPath) {
            let manifestContent = await deps.fs.readFile(manifestPath, ~options={encoding: "utf8"})
            Manifest.parse(manifestContent)
          } else {
            Error("manifest missing")
          }

          let entries = try {
            await deps.fs.readdir(generatorDir, ~options={withFileTypes: false})
          } catch {
          | _ => []
          }
          let actionDirs =
            await Promise.all(entries->Array.map(async entry => {
              let maybeDir = deps.path.join(generatorDir, entry)
              let stat = try {
                Some(await deps.fs.stat(maybeDir))
              } catch {
              | _ => None
              }
              switch stat {
              | Some(s) if s.isDirectory() => Some(maybeDir)
              | _ => None
              }
            }))
          let templates =
            await Promise.all(actionDirs->Array.filterMap(x => x)->Array.map(async actionDir => {
              let files = try {
                await deps.fs.readdir(actionDir, ~options={withFileTypes: false})
              } catch {
              | _ => []
              }
              files
              ->Array.filter(Template.isTemplateFile)
              ->Array.map(filename => deps.path.join(actionDir, filename))
            }))

          let templatePaths = templates->Array.reduce([], (acc, current) => acc->Array.concat(current))

          Console.log("Generator: " ++ generatorName)
          Console.log("Path: " ++ generatorDir)

          Console.log("Prompts:")
          switch manifestResult {
          | Ok(manifest) =>
            switch manifest.prompts {
            | Some(prompts) if Array.length(prompts) > 0 =>
              prompts->Array.forEach(prompt => {
                let promptType = Manifest.promptTypeToString(prompt.promptType)
                Console.log("  - " ++ prompt.name ++ " (" ++ promptType ++ ")")
              })
            | _ => Console.log("  (none)")
            }
          | Error(_) => Console.log("  (manifest missing or invalid)")
          }

          Console.log("Templates:")
          if Array.length(templatePaths) == 0 {
            Console.log("  (none)")
          } else {
            templatePaths->Array.forEach(templatePath => Console.log("  - " ++ templatePath))
          }
        }
      }
    }
  }
}

let runAddPrompt: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
  switch requireGeneratorName(~deps, ~name) {
  | None => ()
  | Some(generatorName) => {
      switch await resolveGeneratorDir(~deps, ~name=generatorName) {
      | None => {
          Console.error("Error: generator not found: " ++ generatorName)
          deps.process.exit(1)
        }
      | Some(generatorDir) => {
          let manifestPath = deps.path.join(generatorDir, "manifest.yaml")
          if !(await deps.fs.fileExists(manifestPath)) {
            Console.error("Error: manifest.yaml not found at " ++ manifestPath)
            deps.process.exit(1)
          } else {
            let promptName = (await deps.interactiveIO.ask("Prompt variable name: "))->String.trim
            let description = (await deps.interactiveIO.ask("Prompt message: "))->String.trim
            let promptTypeInput = await deps.interactiveIO.ask("Prompt type [input/select/confirm/multi-select] (default: input): ")
            let promptType = Manifest.parsePromptTypeFromInput(promptTypeInput)

            let defaultValue = await deps.interactiveIO.ask("Default value (optional): ")
            let whenExpr = await deps.interactiveIO.ask("Show condition (optional EJS expression): ")

            let options = switch promptType {
            | Manifest.Select | Manifest.MultiSelect => {
                let rawOptions =
                  await deps.interactiveIO.ask(
                    "Options (comma-separated, optional label:value format): ",
                  )
                parsePromptOptions(rawOptions)
              }
            | _ => None
            }

            let validatePattern = await deps.interactiveIO.ask("Validation regex (optional): ")
            let validateMessage =
              if validatePattern->String.trim == "" {
                ""
              } else {
                await deps.interactiveIO.ask("Validation error message: ")
              }

            if promptName == "" || description == "" {
              Console.error("Error: prompt name and message are required")
              deps.process.exit(1)
            } else {
              let prompt: Manifest.prompt = {
                name: promptName,
                promptType,
                description,
                default: ?maybeString(defaultValue),
                when_: ?maybeString(whenExpr),
                options: ?options,
                validate: ?parsePromptValidation(validatePattern, validateMessage),
              }

              let manifestContent = await deps.fs.readFile(manifestPath, ~options={encoding: "utf8"})
              switch Manifest.appendPromptPreservingComments(~yamlContent=manifestContent, ~prompt) {
              | Error(e) => {
                  Console.error("Error: " ++ e)
                  deps.process.exit(1)
                }
              | Ok(updated) => {
                  await deps.fs.writeFile(manifestPath, updated)
                  Console.log("Added prompt '" ++ promptName ++ "' to " ++ manifestPath)
                }
              }
            }
          }
        }
      }
    }
  }
}

type directiveValues = {
  toPath: string,
  from: string,
  inject: string,
  after: string,
  before: string,
  atLine: string,
  skipIf: string,
  prepend: bool,
  append: bool,
  eofLast: bool,
  force: bool,
  unlessExists: bool,
  tool: string,
  fetch: string,
  script: string,
  body: string,
}

type directiveKind = StringField | ConfirmField

type directiveDescriptor = {
  key: string,
  yamlKey: string,
  prompt: string,
  kind: directiveKind,
}

let allDirectiveDescriptors: array<directiveDescriptor> = [
  {key: "from", yamlKey: "from", prompt: "from path: ", kind: StringField},
  {key: "inject", yamlKey: "inject", prompt: "inject regex: ", kind: StringField},
  {key: "after", yamlKey: "after", prompt: "after regex: ", kind: StringField},
  {key: "before", yamlKey: "before", prompt: "before regex: ", kind: StringField},
  {key: "at_line", yamlKey: "at_line", prompt: "at_line number: ", kind: StringField},
  {key: "skip_if", yamlKey: "skip_if", prompt: "skip_if regex: ", kind: StringField},
  {key: "tool", yamlKey: "tool", prompt: "tool name: ", kind: StringField},
  {key: "fetch", yamlKey: "fetch", prompt: "fetch URL: ", kind: StringField},
  {key: "script", yamlKey: "script", prompt: "script name (resolved from shell.scripts): ", kind: StringField},
  {key: "prepend", yamlKey: "prepend", prompt: "Enable prepend: true?", kind: ConfirmField},
  {key: "append", yamlKey: "append", prompt: "Enable append: true?", kind: ConfirmField},
  {key: "eof_last", yamlKey: "eof_last", prompt: "Enable eof_last: true?", kind: ConfirmField},
  {key: "force", yamlKey: "force", prompt: "Enable force: true?", kind: ConfirmField},
  {key: "unless_exists", yamlKey: "unless_exists", prompt: "Enable unless_exists: true?", kind: ConfirmField},
]

let buildFrontmatter: directiveValues => string = vals => {
  let frontmatterLines = ["---", "to: " ++ vals.toPath]

  allDirectiveDescriptors->Array.forEach(desc => {
    switch desc.kind {
    | StringField => {
        let fieldVal = switch desc.key {
        | "from" => vals.from
        | "inject" => vals.inject
        | "after" => vals.after
        | "before" => vals.before
        | "at_line" => vals.atLine
        | "skip_if" => vals.skipIf
        | "tool" => vals.tool
        | "fetch" => vals.fetch
        | "script" => vals.script
        | _ => ""
        }
        if fieldVal->String.trim != "" {
          Js.Array.push(desc.yamlKey ++ ": " ++ fieldVal->String.trim, frontmatterLines)->ignore
        }
      }
    | ConfirmField => {
        let boolVal = switch desc.key {
        | "prepend" => vals.prepend
        | "append" => vals.append
        | "eof_last" => vals.eofLast
        | "force" => vals.force
        | "unless_exists" => vals.unlessExists
        | _ => false
        }
        if boolVal {
          Js.Array.push(desc.yamlKey ++ ": true", frontmatterLines)->ignore
        }
      }
    }
  })

  Js.Array.push("---", frontmatterLines)->ignore
  frontmatterLines->Array.concat([vals.body])->Array.join("\n") ++ "\n"
}

let promptForDirectives: (
  ~io: Ports.interactiveIO,
  ~toPath: string,
) => promise<directiveValues> = async (~io, ~toPath) => {
  let directiveSelection =
    await io.ask(
      "Additional directives (comma-separated; e.g. inject,after,before,atLine,skipIf,prepend,append,eofLast,force,unlessExists,tool,fetch,script): ",
    )
  let selected = parseDirectiveSelection(directiveSelection)

  // Accumulate string and bool values
  let stringVals = Dict.make()
  let boolVals = Dict.make()

  let idx = ref(0)
  while idx.contents < Array.length(allDirectiveDescriptors) {
    switch allDirectiveDescriptors[idx.contents] {
    | Some(desc) =>
      if hasDirective(~selected, ~key=desc.key) {
        switch desc.kind {
        | StringField => {
            let answer = await io.ask(desc.prompt)
            Dict.set(stringVals, desc.key, answer)
          }
        | ConfirmField => {
            let answer = await io.askConfirm(~question=desc.prompt, ~defaultYes=true)
            Dict.set(boolVals, desc.key, answer)
          }
        }
      }
    | None => ()
    }
    idx.contents = idx.contents + 1
  }

  let body = await io.ask("Template body (single-line; optional): ")

  {
    toPath,
    from: Dict.get(stringVals, "from")->Option.getOr(""),
    inject: Dict.get(stringVals, "inject")->Option.getOr(""),
    after: Dict.get(stringVals, "after")->Option.getOr(""),
    before: Dict.get(stringVals, "before")->Option.getOr(""),
    atLine: Dict.get(stringVals, "at_line")->Option.getOr(""),
    skipIf: Dict.get(stringVals, "skip_if")->Option.getOr(""),
    prepend: Dict.get(boolVals, "prepend")->Option.getOr(false),
    append: Dict.get(boolVals, "append")->Option.getOr(false),
    eofLast: Dict.get(boolVals, "eof_last")->Option.getOr(false),
    force: Dict.get(boolVals, "force")->Option.getOr(false),
    unlessExists: Dict.get(boolVals, "unless_exists")->Option.getOr(false),
    tool: Dict.get(stringVals, "tool")->Option.getOr(""),
    fetch: Dict.get(stringVals, "fetch")->Option.getOr(""),
    script: Dict.get(stringVals, "script")->Option.getOr(""),
    body,
  }
}

let runAddFile: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
  switch requireGeneratorName(~deps, ~name) {
  | None => ()
  | Some(generatorName) => {
      switch await resolveGeneratorDir(~deps, ~name=generatorName) {
      | None => {
          Console.error("Error: generator not found: " ++ generatorName)
          deps.process.exit(1)
        }
      | Some(generatorDir) => {
          let actionFolderRaw = await deps.interactiveIO.ask("Action folder (default: new): ")
          let actionFolder = switch maybeString(actionFolderRaw) {
          | Some(v) => v
          | None => "new"
          }

          let filenameRaw = await deps.interactiveIO.ask("Template file name (e.g. index.ejs.t): ")
          let filename = normalizeTemplateFilename(filenameRaw->String.trim)
          let toPath = (await deps.interactiveIO.ask("to path (required): "))->String.trim

          if filename == ".ejs.t" || toPath == "" {
            Console.error("Error: template file name and 'to' are required")
            deps.process.exit(1)
          } else {
            let directives = await promptForDirectives(~io=deps.interactiveIO, ~toPath)
            let templateContent = buildFrontmatter(directives)

            let actionDir = deps.path.join(generatorDir, actionFolder)
            let targetPath = deps.path.join(actionDir, filename)
            let _ = await deps.fs.mkdir(actionDir, ~options={recursive: true})
            await deps.fs.writeFile(targetPath, templateContent)
            Console.log("Created template: " ++ targetPath)
          }
        }
      }
    }
  }
}

let run: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  let action = switch args[0] {
  | Some(a) => a
  | None => ""
  }

  let name = switch args[1] {
  | Some(n) if !String.startsWith(n, "-") => Some(n)
  | _ => None
  }

  switch action {
  | "" => {
      Help.printHelpFor("generator")
      deps.process.exit(0)
    }
  | "list" => await runList(~deps, ~name)
  | "add-prompt" => await runAddPrompt(~deps, ~name)
  | "add-file" => await runAddFile(~deps, ~name)
  | _ => {
      Console.error("Error: unknown generator action \"" ++ action ++ "\"")
      Help.printHelpFor("generator")
      deps.process.exit(1)
    }
  }
}
