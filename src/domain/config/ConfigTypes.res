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
  dryRun?: bool,
  shell?: shellConfig,
}

type templateSource = {
  name: string,
  source: string,
  path: string,
}

// Global config (loaded from ~/.config/blueprint/config.yaml)
// WS4: `allowDangerousCommands` removed. WS2 ExecPolicy is the single
// authority over which shell commands may run (via args[] or exact
// allowlist match); config no longer carries a bypass key.
type globalConfig = {
  templates: array<string>,
  forceOverwrite: bool,
  dryRun: bool,
  timeout: int,
  defaultAttributes: dict<string>,
  registry: array<templateSource>,
}

// Merged config — effective values after project overrides global
type mergedConfig = {
  templates: array<string>,         // from global (no project override for templates)
  forceOverwrite: bool,             // project or global
  dryRun: bool,                     // project or global
  timeout: int,                     // project hooks.timeout or global
  defaultAttributes: dict<string>,  // global defaults with project overrides
  shell?: shellConfig,              // merged shell config
}

let defaultGlobalConfig: globalConfig = {
  templates: [],
  forceOverwrite: false,
  dryRun: false,
  timeout: 5,
  defaultAttributes: Dict.make(),
  registry: [],
}