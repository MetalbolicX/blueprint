// EJS template rendering with func helpers injected as h.*

open Template
open FuncMap

type renderContext = {
  name: string,
  pascalName: string,
  names: string,
  pluralPascalName: string,
  cwd: string,
  actionfolder: string,
  attributes: dict<string>,
}

// Extract variable name from EJS "not defined" error messages
let _extractUndefinedVar: string => option<string> = msg => {
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
    Some(String.slice(msg, ~start=varStart.contents, ~end=varEnd))
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
  Dict.set(data, "cwd", ctx.cwd)
  Dict.set(data, "actionfolder", ctx.actionfolder)

  // Merge attributes
  Dict.toArray(ctx.attributes)->Array.forEach(((k, v)) => {
    Dict.set(data, k, v)
  })

  // Set h helper object
  let hObj = Dict.make()
  Dict.set(hObj, "pascalCase", helpers.pascalCase->Obj.magic)
  Dict.set(hObj, "camelCase", helpers.camelCase->Obj.magic)
  Dict.set(hObj, "kebabCase", helpers.kebabCase->Obj.magic)
  Dict.set(hObj, "snakeCase", helpers.snakeCase->Obj.magic)
  Dict.set(hObj, "upper", helpers.upper->Obj.magic)
  Dict.set(hObj, "lower", helpers.lower->Obj.magic)
  Dict.set(hObj, "trim", helpers.trim->Obj.magic)
  Dict.set(hObj, "title", helpers.title->Obj.magic)
  Dict.set(data, "h", hObj->Obj.magic)

  try {
    let rendered = Bindings.Ejs.render(tmpl.body, data->Obj.magic)
    Ok(rendered)
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Unknown render error"
    }
    let enhanced = switch _extractUndefinedVar(msg) {
    | Some(varName) =>
      "Template variable '" ++ varName ++ "' is required but was not provided. "
      ++ "Pass it via --" ++ varName ++ " <value> on the command line."
    | None => msg
    }
    Error(enhanced)
  }
}
