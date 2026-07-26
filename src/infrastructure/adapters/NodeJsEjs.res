/**
 * NodeJsEjs — Node.js EJS adapter implementing Ports.ejs.
 */

open Ports

let make: unit => ejs = () => {
  renderString: (~template, ~context) => {
    try {
      let rendered = Bindings.Ejs.render(template, context)
      Ok(rendered)
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "EJS render error"
      }
      Error(msg)
    }
  },
  renderFile: (~path, ~context) => {
    let p: promise<string> = Bindings.Ejs.renderFile(path, context)
    p
    ->Promise.then(ok => Promise.resolve(Ok(ok)))
    ->Promise.catch(e => {
      let msg = Errors.extractErrorMessage(e)
      Promise.resolve(Error(msg))
    })
  },
}
