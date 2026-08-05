// EJS escape/client/outputFunctionName options are intentionally NOT exposed — they are RCE primitives if fed untrusted input.
type options = {
  delimiter?: string,
}

// Node's CJS->ESM interop exposes `ejs` only via the default export (the whole
// module.exports object). Binding directly to the named export "render" yields
// undefined under native ESM. We therefore grab the default export as a handle
// and invoke render/renderFile as methods on it via @send.
type t

@module("ejs")
external ejs: t = "default"

@send
external renderOn: (t, string, dict<string>, ~options: options=?) => string = "render"
@send
external renderFileOn: (t, string, dict<string>, ~options: options=?) => promise<string> = "renderFile"

let render = (template, data, ~options=?) => renderOn(ejs, template, data, ~options=?options)
let renderFile = (path, data, ~options=?) => renderFileOn(ejs, path, data, ~options=?options)