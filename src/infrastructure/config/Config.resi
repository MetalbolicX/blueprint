type shellTool = {
  name: string,
  command: string,
  args?: array<string>,
}

type scriptDef = {
  name: string,
  path: string,
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
  scripts?: array<scriptDef>,
  env?: shellEnv,
}

type config = {
  hooks?: hooksConfig,
  output?: string,
  shell?: shellConfig,
}

type templateSource = {
  name: string,
  source: string,
  path: string,
}

type globalConfig = {
  templates: array<string>,
  allowDangerousCommands: bool,
  forceOverwrite: bool,
  dryRun: bool,
  timeout: int,
  defaultAttributes: dict<string>,
  registry: array<templateSource>,
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
let loadFrom: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<result<option<config>, string>>
let loadGlobal: (~fs: Ports.fileSystem, ~path: Ports.path, ~homeDir: string) => promise<result<option<globalConfig>, string>>
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig
let validateMergedConfig: mergedConfig => result<unit, string>
let defaultGlobalConfig: globalConfig
let saveGlobalAtPath: (~fs: Ports.fileSystem, ~path: Ports.path, ~configPath: string, globalConfig) => promise<result<unit, string>>
let saveGlobal: (~fs: Ports.fileSystem, ~path: Ports.path, ~homeDir: string, globalConfig) => promise<result<unit, string>>
let defaultOutputDir: string
let defaultTimeout: int
