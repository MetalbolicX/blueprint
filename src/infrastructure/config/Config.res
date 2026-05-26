// Config — Re-export facade for backwards compatibility
// Split from Config.res as part of T2 refactor
// Types re-exported from ConfigTypes
// Functions re-exported from ConfigParser and ConfigStore

module ConfigTypes = ConfigTypes
module ConfigParser = ConfigParser
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

// Function re-exports (from ConfigParser)
let parse: string => result<config, string> = ConfigParser.parse
let parseGlobal: string => result<globalConfig, string> = ConfigParser.parseGlobal
let parseHookCommand: JSON.t => option<hookCommand> = ConfigParser.parseHookCommand
let parseHooks: JSON.t => option<hooksConfig> = ConfigParser.parseHooks
let parseShellConfig: JSON.t => option<shellConfig> = ConfigParser.parseShellConfig
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig = ConfigParser.mergeConfig
let validateMergedConfig: mergedConfig => result<unit, string> = ConfigParser.validateMergedConfig
let defaultOutputDir: string = ConfigParser.defaultOutputDir
let defaultTimeout: int = ConfigParser.defaultTimeout

// Function re-exports (from ConfigStore)
let loadFrom: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<result<option<config>, string>> = ConfigStore.loadFrom
let loadGlobal: (~fs: Ports.fileSystem, ~homeDir: string) => promise<result<option<globalConfig>, string>> = ConfigStore.loadGlobal
let saveGlobalAtPath: (~fs: Ports.fileSystem, ~path: Ports.path, ~configPath: string, globalConfig) => promise<result<unit, string>> = ConfigStore.saveGlobalAtPath
let saveGlobal: (~fs: Ports.fileSystem, ~path: Ports.path, ~homeDir: string, globalConfig) => promise<result<unit, string>> = ConfigStore.saveGlobal