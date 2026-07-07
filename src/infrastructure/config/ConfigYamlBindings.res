// ConfigYamlBindings.res - Low-level YAML parsing and stringification


let parse: string => JSON.t = Bindings.Yaml.parse
let stringify: JSON.t => string = Bindings.Yaml.stringify
