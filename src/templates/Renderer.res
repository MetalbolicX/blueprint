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
    Error(msg)
  }
}
