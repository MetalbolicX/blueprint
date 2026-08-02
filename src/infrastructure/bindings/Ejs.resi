// EJS escape/client/outputFunctionName options are intentionally NOT exposed — they are RCE primitives if fed untrusted input.
type options = {
  delimiter?: string,
}

let render: (string, dict<string>, ~options: options=?) => string
let renderFile: (string, dict<string>, ~options: options=?) => promise<string>
