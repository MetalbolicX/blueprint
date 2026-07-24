/**
 * Node.js util bindings interface
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

let parseArgs: parseConfig => parseResults
let inspect: 'a => string
let parseOptions: (~short: string=?, ~default: defaultValue=?, unit) => flagConfig
let getString: (cliOptions, string) => option<string>
let getBool: (cliOptions, string) => bool
