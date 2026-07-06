// Config — Re-export facade for backwards compatibility
// Split from Config.res as part of T2 refactor
// Types re-exported from ConfigTypes
// Functions re-exported from ConfigYaml (parsing) and ConfigStore (I/O)

module ConfigTypes = ConfigTypes
module ConfigStore = ConfigStore

// Type re-exports (from ConfigTypes — using type aliases, NOT module re-exports)
type shellTool = ConfigTypes.shellTool
type scriptDef = ConfigTypes.scriptDef
type shellEnv = ConfigTypes.shellEnv
type hookCommand = ConfigTypes.hookCommand
type hooksConfig = ConfigTypes.hooksConfig
type shellConfig = ConfigTypes.shellConfig
type config = ConfigTypes.config
type templateSource = ConfigTypes.templateSource
type globalConfig = ConfigTypes.globalConfig
type mergedConfig = ConfigTypes.mergedConfig

// Default global config
let defaultGlobalConfig: globalConfig = ConfigTypes.defaultGlobalConfig

// Function re-exports (from ConfigYaml — WS4 consolidation)
let parse: string => result<config, string> = ConfigYaml.parseConfig
let parseGlobal: string => result<globalConfig, string> = ConfigYaml.parseGlobal
let parseHookCommand: JSON.t => option<hookCommand> = ConfigYaml.parseHookCommand
let parseHooks: JSON.t => option<hooksConfig> = ConfigYaml.parseHooks
let parseShellConfig: JSON.t => option<shellConfig> = ConfigYaml.parseShellConfig
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig = ConfigYaml.mergeConfig
let validateMergedConfig: mergedConfig => result<unit, string> = ConfigYaml.validateMergedConfig
let defaultOutputDir: string = ConfigYaml.defaultOutputDir
let defaultTimeout: int = ConfigYaml.defaultTimeout

// Function re-exports (from ConfigStore)
let loadFrom: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<result<option<config>, string>> = ConfigStore.loadFrom
let loadGlobal: (~fs: Ports.fileSystem, ~path: Ports.path, ~homeDir: string) => promise<result<option<globalConfig>, string>> = ConfigStore.loadGlobal
let saveGlobalAtPath: (~fs: Ports.fileSystem, ~path: Ports.path, ~configPath: string, globalConfig) => promise<result<unit, string>> = ConfigStore.saveGlobalAtPath
let saveGlobal: (~fs: Ports.fileSystem, ~path: Ports.path, ~homeDir: string, globalConfig) => promise<result<unit, string>> = ConfigStore.saveGlobal