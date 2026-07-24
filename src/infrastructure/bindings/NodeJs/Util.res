/**
 * Node.js util bindings — utility functions
 */

@unboxed
type defaultValue =
  | String(string)
  | Bool(bool)

type flagConfig = {
  @as("type") type_: string,
  short?: string,
  default?: defaultValue,
  multiple?: bool,
}

type cliOptions = {
  help?: bool,
  version?: bool,
  name?: string,
  input?: string,
  output?: string,
  format?: string,
  verbose?: bool,
}

type parseResults = {
  values: cliOptions,
  positionals: array<string>,
}

type parseConfig = {
  args: array<string>,
  options: dict<flagConfig>,
  strict?: bool,
  allowPositionals?: bool,
  tokens?: bool,
}

@module("node:util")
external parseArgs: parseConfig => parseResults = "parseArgs"

@module("node:util")
external inspect: 'a => string = "inspect"

let parseOptions: (~short: string=?, ~default: defaultValue=?, unit) => flagConfig = (
  ~short=?,
  ~default=?,
  (),
) => {
  type_: "string",
  ?short,
  ?default,
}

let getString: (cliOptions, string) => option<string> = (values, key) => {
  switch key {
  | "name" => values.name
  | "input" => values.input
  | "output" => values.output
  | "format" => values.format
  | _ => None
  }
}

let getBool: (cliOptions, string) => bool = (values, key) => {
  switch key {
  | "help" => values.help->Option.getOr(false)
  | "version" => values.version->Option.getOr(false)
  | "verbose" => values.verbose->Option.getOr(false)
  | _ => false
  }
}
