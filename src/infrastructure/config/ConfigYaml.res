// ConfigYaml -- YAML binding adapter for the config subsystem.
// Single owner of the YAML binding layer (WS2 extraction from ConfigParser).

let parse: string => JSON.t = Bindings.Yaml.parse
let stringify: JSON.t => string = Bindings.Yaml.stringify