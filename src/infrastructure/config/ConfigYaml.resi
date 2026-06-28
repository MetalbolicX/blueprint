// ConfigYaml -- YAML binding adapter for the config subsystem.
// Single owner of Bindings.Yaml calls (WS2 extraction from ConfigParser).

/** Parse a YAML document string into JSON. Wraps Bindings.Yaml.parse. */
let parse: string => JSON.t

/** Serialize a JSON value to a YAML string. Wraps Bindings.Yaml.stringify. */
let stringify: JSON.t => string