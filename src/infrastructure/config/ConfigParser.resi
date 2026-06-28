// ConfigParser — Interface
// Extracted from Config.res as part of T2 refactor

open ConfigTypes

let parse: string => result<config, string>
let parseGlobal: string => result<globalConfig, string>
let parseHookCommand: JSON.t => option<hookCommand>
let parseHooks: JSON.t => option<hooksConfig>
let parseShellConfig: JSON.t => option<shellConfig>
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig
let validateMergedConfig: mergedConfig => result<unit, string>
let defaultOutputDir: string
let defaultTimeout: int