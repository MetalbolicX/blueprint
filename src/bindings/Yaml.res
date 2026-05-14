@module("yaml")
external parse: string => JSON.t = "parse"

@module("yaml")
external stringify: 'a => string = "stringify"

type documentOptions = {
  indent: option<int>,
  lineWidth: option<int>,
  singleQuote: option<bool>,
}

@module("yaml")
external parseWithOptions: (string, ~options: documentOptions=?) => JSON.t = "parse"

@module("yaml")
external stringifyWithOptions: ('a, ~options: documentOptions=?) => string = "stringify"
