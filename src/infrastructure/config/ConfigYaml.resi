// ConfigYaml.resi
open ConfigTypes

// Exposing the public API of the refactored config subsystem
let parse: string => result<config, string>
let parseGlobal: string => result<globalConfig, string>
let serializeGlobalConfig: globalConfig => string
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig
let validateMergedConfig: mergedConfig => result<unit, string>

let defaultOutputDir: string
let defaultTimeout: int

// Optionally expose sub-modules if needed
module Bindings: module type of ConfigYamlBindings
module Serializer: module type of ConfigYamlSerializer
module JsonParser: module type of ConfigJsonParser
module Parser: module type of ConfigYamlParser
module Logic: module type of ConfigLogic
