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

let parseArgs: parseArgsConfig => parsedArgs
let parseOptions: (~short: string=?, ~default: string=?, unit) => optionConfig
let getString: (parsedValues, string) => option<string>
let getBool: (parsedValues, string) => bool
