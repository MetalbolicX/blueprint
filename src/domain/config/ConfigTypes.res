// ConfigTypes — All type definitions for blueprint config
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

// Global config (loaded from ~/.config/blueprint/config.yaml)
type globalConfig = {
  templates: array<string>,
  allowDangerousCommands: bool,
  forceOverwrite: bool,
  dryRun: bool,
  timeout: int,
  defaultAttributes: dict<string>,
  registry: array<templateSource>,
}

// Merged config — effective values after project overrides global
type mergedConfig = {
  templates: array<string>,         // from global (no project override for templates)
  allowDangerousCommands: bool,    // project or global
  forceOverwrite: bool,             // project or global
  dryRun: bool,                     // project or global
  timeout: int,                     // project hooks.timeout or global
  defaultAttributes: dict<string>,  // global defaults with project overrides
  shell?: shellConfig,              // merged shell config
}

let defaultGlobalConfig: globalConfig = {
  templates: [],
  allowDangerousCommands: false,
  forceOverwrite: false,
  dryRun: false,
  timeout: 5,
  defaultAttributes: Dict.make(),
  registry: [],
}