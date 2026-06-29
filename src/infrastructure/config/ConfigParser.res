// ConfigParser — Delegation shell (WS4). All parsing logic moved to ConfigYaml.
// Preserved as a public module so direct callers (ConfigStore.res L63, L93)
// resolve without caller edits. ConfigParser.resi is unchanged.

open ConfigTypes

let parseGlobal = ConfigYaml.parseGlobal
let parse = ConfigYaml.parseConfig
let parseHookCommand = ConfigYaml.parseHookCommand
let parseHooks = ConfigYaml.parseHooks
let parseShellConfig = ConfigYaml.parseShellConfig
let mergeConfig = ConfigYaml.mergeConfig
let validateMergedConfig = ConfigYaml.validateMergedConfig
let defaultOutputDir = ConfigYaml.defaultOutputDir
let defaultTimeout = ConfigYaml.defaultTimeout