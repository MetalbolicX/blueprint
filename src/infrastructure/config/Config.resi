type shellTool = {
  name: string,
  command: string,
  args?: array<string>,
}

type shellEnv = {
  vars: dict<string>,
}

type hookCommand = {
  command: string,
  args?: array<string>,
}

type hooksConfig = {
  preGenerate?: hookCommand,
  postGenerate?: hookCommand,
  timeout?: int,
}

type shellConfig = {
  enabled: bool,
  tools?: array<shellTool>,
  env?: shellEnv,
}

type config = {
  hooks?: hooksConfig,
  output?: string,
  shell?: shellConfig,
}

type globalConfig = {
  templates: array<string>,
  allowDangerousCommands: bool,
  forceOverwrite: bool,
  dryRun: bool,
  timeout: int,
  defaultAttributes: dict<string>,
}

type mergedConfig = {
  templates: array<string>,
  allowDangerousCommands: bool,
  forceOverwrite: bool,
  dryRun: bool,
  timeout: int,
  defaultAttributes: dict<string>,
  shell?: shellConfig,
}

let parse: string => result<config, string>
let parseGlobal: string => result<globalConfig, string>
let loadFrom: string => promise<result<option<config>, string>>
let loadGlobal: unit => promise<result<option<globalConfig>, string>>
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig
let defaultGlobalConfig: globalConfig
let defaultOutputDir: string
let defaultTimeout: int