// EJS template rendering with func helpers injected as h.*

open Template
open FuncMap

// WS4: cwd and actionfolder removed from the renderContext type. Template
// rendering must not expose host filesystem paths; both fields are stripped
// at `Context.toRenderContext` (src/domain/context/Context.res).
type renderContext = {
  name: string,
  pascalName: string,
  names: string,
  pluralPascalName: string,
  attributes: dict<string>,
}

// Extract variable name from EJS "not defined" error messages
let extractUndefinedVar: string => option<string> = msg => {
  let marker = " is not defined"
  switch Js.String.indexOf(marker, msg) {
  | -1 => None
  | idx =>
    let varEnd = idx
    let varStart = ref(varEnd)
    let i = ref(varEnd - 1)
    while i.contents >= 0 {
      let ch = String.getUnsafe(msg, i.contents)
      if ch >= "a" && ch <= "z" || ch >= "A" && ch <= "Z" || ch >= "0" && ch <= "9" || ch == "_" || ch == "$" {
        varStart := i.contents
        i := i.contents - 1
      } else {
        i := -1
      }
    }
    let name = String.slice(msg, ~start=varStart.contents, ~end=varEnd)
    if String.length(name) > 0 { Some(name) } else { None }
  }
}

let render: (template, renderContext) => result<string, string> = (tmpl, ctx) => {
  let helpers = makeHelpers()

  // Build EJS data object — merge name variants, attributes, and h helper
  let data = Dict.make()

  Dict.set(data, "name", ctx.name)
  Dict.set(data, "Name", ctx.pascalName)
  Dict.set(data, "names", ctx.names)
  Dict.set(data, "Names", ctx.pluralPascalName)

  // Merge attributes
  Dict.toArray(ctx.attributes)->Array.forEach(((k, v)) => {
    Dict.set(data, k, v)
  })

  // Set h helper object
  Dict.set(data, "h", FuncMap.makeHelpersDict()->Obj.magic)

  try {
    let rendered = Bindings.Ejs.render(tmpl.body, data->Obj.magic)
    Ok(rendered)
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Unknown render error"
    }
    let enhanced = switch extractUndefinedVar(msg) {
    | Some(varName) if String.length(varName) > 0 =>
      "Template variable '" ++ varName ++ "' is required but was not provided. "
      ++ "Pass it via --" ++ varName ++ " <value> on the command line."
    | _ => msg
    }
    Error(enhanced)
  }
}
