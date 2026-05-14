// EJS template rendering with func helpers injected as h.*

open Template
open FuncMap

type renderContext = {
  name: string,
  Name: string,
  names: string,
  Names: string,
  cwd: string,
  actionfolder: string,
  attributes: Js.Dict.t<string>,
}

let render: (template, renderContext) => result<string, string> = (tmpl, ctx) => {
  let helpers = makeHelpers()

  // Build EJS data object — merge name variants, attributes, and h helper
  let data = Js.Dict.empty()

  Js.Dict.set(data, "name", ctx.name)
  Js.Dict.set(data, "Name", ctx.Name)
  Js.Dict.set(data, "names", ctx.names)
  Js.Dict.set(data, "Names", ctx.Names)
  Js.Dict.set(data, "cwd", ctx.cwd)
  Js.Dict.set(data, "actionfolder", ctx.actionfolder)

  // Merge attributes
  Js.Json.stringifyExplore(Js.Json.parseOrNull(Js.Json.object_(ctx.attributes)), (key, value) => {
    switch Js.Json.classify(value) {
    | Js.Json.JString(s) => Some(Js.Json.JString(s))
    | _ => Some(value)
    }
  })->ignore

  // Set h helper object
  let hObj = Js.Dict.empty()
  Js.Dict.set(hObj, "pascalCase", Js.Json.JString(helpers.pascalCase->Obj.magic))
  Js.Dict.set(hObj, "camelCase", Js.Json.JString(helpers.camelCase->Obj.magic))
  Js.Dict.set(hObj, "kebabCase", Js.Json.JString(helpers.kebabCase->Obj.magic))
  Js.Dict.set(hObj, "snakeCase", Js.Json.JString(helpers.snakeCase->Obj.magic))
  Js.Dict.set(hObj, "upper", Js.Json.JString(helpers.upper->Obj.magic))
  Js.Dict.set(hObj, "lower", Js.Json.JString(helpers.lower->Obj.magic))
  Js.Dict.set(hObj, "trim", Js.Json.JString(helpers.trim->Obj.magic))
  Js.Dict.set(hObj, "title", Js.Json.JString(helpers.title->Obj.magic))
  Js.Dict.set(data, "h", Js.Json.object_(hObj))

  try {
    let rendered = Bindings.Ejs.render(tmpl.body, data, ())
    Ok(rendered)
  } catch {
  | Js.Exn.Error(obj) =>
    let msg = switch Js.Exn.message(obj) {
    | Some(m) => m
    | None => "Unknown render error"
    }
    Error(msg)
  }
}