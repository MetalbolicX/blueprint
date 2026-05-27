type document

type documentOptions = {
  indent?: int,
  lineWidth?: int,
  singleQuote?: bool,
}

let parse: string => JSON.t
let stringify: 'a => string
let parseDocument: string => document
let documentToString: document => string
let addIn: (document, array<string>, 'a) => unit
let addInAtPath: (document, array<JSON.t>, 'a) => unit
let hasErrors: document => bool
let parseWithOptions: (string, ~options: documentOptions=?) => JSON.t
let stringifyWithOptions: ('a, ~options: documentOptions=?) => string
