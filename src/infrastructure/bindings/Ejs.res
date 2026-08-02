// EJS escape/client/outputFunctionName options are intentionally NOT exposed — they are RCE primitives if fed untrusted input.
type options = {
  delimiter?: string,
}

@module("ejs")
external render: (string, dict<string>, ~options: options=?) => string = "render"

@module("ejs")
external renderFile: (string, dict<string>, ~options: options=?) => promise<string> = "renderFile"
