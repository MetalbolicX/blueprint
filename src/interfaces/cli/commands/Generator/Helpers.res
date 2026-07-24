// Helpers — shared utilities for generator commands
let projectGeneratorSearchPaths = ["_templates", "templates", "generators"]

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

let normalizeTemplateFilename = (filename: string) => {
  if String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl") {
    filename
  } else {
    filename ++ ".ejs.t"
  }
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
