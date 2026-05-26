// ConfigTypes — Interface
// Extracted from Config.res as part of T2 refactor

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

let defaultGlobalConfig: globalConfig