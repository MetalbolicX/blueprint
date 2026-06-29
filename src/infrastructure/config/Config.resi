// Config — Interface (re-export facade for backwards compatibility)
// Split from Config.res as part of T2 refactor

module ConfigTypes = ConfigTypes
module ConfigParser = ConfigParser
module ConfigStore = ConfigStore

// Type re-exports (from ConfigTypes)
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
let defaultGlobalConfig: globalConfig

// Function re-exports (from ConfigYaml — WS4 consolidation)
let parse: string => result<config, string>
let parseGlobal: string => result<globalConfig, string>
let parseHookCommand: JSON.t => option<hookCommand>
let parseHooks: JSON.t => option<hooksConfig>
let parseShellConfig: JSON.t => option<shellConfig>
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig
let validateMergedConfig: mergedConfig => result<unit, string>
let defaultOutputDir: string
let defaultTimeout: int

// Function re-exports (from ConfigStore)
let loadFrom: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<result<option<config>, string>>
let loadGlobal: (~fs: Ports.fileSystem, ~homeDir: string) => promise<result<option<globalConfig>, string>>
let saveGlobalAtPath: (~fs: Ports.fileSystem, ~path: Ports.path, ~configPath: string, globalConfig) => promise<result<unit, string>>
let saveGlobal: (~fs: Ports.fileSystem, ~path: Ports.path, ~homeDir: string, globalConfig) => promise<result<unit, string>>