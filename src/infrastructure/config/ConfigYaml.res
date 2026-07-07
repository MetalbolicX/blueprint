// ConfigYaml - Facade for the config YAML subsystem


// Re-exporting key functionalities from the new modules
module Bindings = ConfigYamlBindings
module Serializer = ConfigYamlSerializer
module JsonParser = ConfigJsonParser
module Parser = ConfigYamlParser
module Logic = ConfigLogic

// Direct exports for convenience
let parse = Parser.parseConfig
let parseGlobal = Parser.parseGlobal
let serializeGlobalConfig = Serializer.serializeGlobalConfig
let mergeConfig = Logic.mergeConfig
let validateMergedConfig = Logic.validateMergedConfig

// Default values that were at the end of the original file
let defaultOutputDir: string = "generated"
let defaultTimeout: int = 5 // seconds
