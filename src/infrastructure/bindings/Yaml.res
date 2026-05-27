@module("yaml")
external parse: string => JSON.t = "parse"

@module("yaml")
external stringify: 'a => string = "stringify"

type document
type documentError

@module("yaml")
external parseDocument: string => document = "parseDocument"

@send
external documentToString: document => string = "toString"

@get
external errors: document => array<documentError> = "errors"

@send
external addIn: (document, array<string>, 'a) => unit = "addIn"

@send
external addInAtPath: (document, array<JSON.t>, 'a) => unit = "addIn"

let hasErrors: document => bool = document => Array.length(errors(document)) > 0

type documentOptions = {
  indent?: int,
  lineWidth?: int,
  singleQuote?: bool,
}

@module("yaml")
external parseWithOptions: (string, ~options: documentOptions=?) => JSON.t = "parse"

@module("yaml")
external stringifyWithOptions: ('a, ~options: documentOptions=?) => string = "stringify"
