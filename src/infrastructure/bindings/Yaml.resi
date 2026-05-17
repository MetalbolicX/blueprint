type documentOptions = {
  indent: option<int>,
  lineWidth: option<int>,
  singleQuote: option<bool>,
}

let parse: string => JSON.t
let stringify: 'a => string
let parseWithOptions: (string, ~options: documentOptions=?) => JSON.t
let stringifyWithOptions: ('a, ~options: documentOptions=?) => string
