// ConfigYamlParser.resi
open ConfigTypes

let parseGlobal: string => result<globalConfig, string>
let parseConfig: string => result<config, string>
