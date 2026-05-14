type optionConfig = {
  \"type": string,
  short: option<string>,
  default: option<Js.Json.t>,
}

type parseArgsConfig = {
  args: option<array<string>>,
  options: option<Js.Dict.t<optionConfig>>,
  strict: option<bool>,
  allowPositionals: option<bool>,
  tokens: option<bool>,
  stopEarly: option<bool>,
  ignoreCrashes: option<bool>,
}

type parsedValues = Js.Dict.t<Js.Json.t>

type parsedArgs = {
  values: parsedValues,
  positionals: array<string>,
  tokens: option<array<Js.Json.t>>,
}

@module("node:util")
external parseArgs: parseArgsConfig => parsedArgs = "parseArgs"

let parseOptions: (~short: string=?, ~default: Js.Json.t=?, unit) => optionConfig = (~short=?, ~default=?, ()) => {
  \"type": "string",
  short: short,
  default: default,
}

let getString: (parsedValues, string) => option<string> = (values, key) => {
  switch Js.Dict.get(values, key) {
  | Some(v) => Js.Json.classify(v) == Js.Json.JString(s) ? Some(s) : None
  | None => None
  }
}

let getBool: (parsedValues, string) => bool = (values, key) => {
  switch Js.Dict.get(values, key) {
  | Some(v) => Js.Json.classify(v) == Js.Json.JTrue ? true : false
  | _ => false
  }
}