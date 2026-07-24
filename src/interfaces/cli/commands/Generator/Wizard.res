// Wizard — interactive directive prompt wizard
module H = Helpers

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
