type documentOptions = {
  indent?: int,
  lineWidth?: int,
  singleQuote?: bool,
}

let parse: string => JSON.t
let stringify: 'a => string
let parseWithOptions: (string, ~options: documentOptions=?) => JSON.t
let stringifyWithOptions: ('a, ~options: documentOptions=?) => string
