type optionConfig = {"type": string, "short": option<string>, "default": option<string>}

type parseArgsConfig = {
  args: option<array<string>>,
  options: option<dict<optionConfig>>,
  strict: option<bool>,
  allowPositionals: option<bool>,
  tokens: option<bool>,
  stopEarly: option<bool>,
  ignoreCrashes: option<bool>,
}

type parsedValues = dict<string>

type parsedArgs = {
  values: parsedValues,
  positionals: array<string>,
  tokens: option<array<string>>,
}

@module("node:util")
external parseArgs: parseArgsConfig => parsedArgs = "parseArgs"

let parseOptions: (~short: string=?, ~default: string=?, unit) => optionConfig = (
  ~short=?,
  ~default=?,
  (),
) =>
  {
    "type": "string",
    "short": short,
    "default": default,
  }

let getString: (parsedValues, string) => option<string> = (values, key) => {
  Dict.get(values, key)
}

let getBool: (parsedValues, string) => bool = (values, key) => {
  switch Dict.get(values, key) {
  | Some(v) => v == "true" || v == "false"
  | None => false
  }
}
