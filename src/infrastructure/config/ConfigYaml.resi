// ConfigYaml -- YAML binding adapter and parsing owner for the config subsystem.
// Single owner of Bindings.Yaml calls (WS2 extraction from ConfigParser).
// Also owns globalConfig -> YAML serialization (WS3 extraction from ConfigParser).
// Also owns all JSON -> domain parsing logic (WS4 consolidation from ConfigParser).

open ConfigTypes

/** Parse a YAML document string into JSON. Wraps Bindings.Yaml.parse. */
let parse: string => JSON.t

/** Serialize a JSON value to a YAML string. Wraps Bindings.Yaml.stringify. */
let stringify: JSON.t => string

/** Serialize a globalConfig to a YAML string. Single owner of config-to-YAML serialization (WS3). */
let serializeGlobalConfig: globalConfig => string

// --- JSON -> domain parsing entry points (moved from ConfigParser -- WS4) ---

/** Parse a YAML document string into a project config. Renamed from ConfigParser.parse to avoid collision with the YAML->JSON parse above. */
let parseConfig: string => result<config, string>

/** Parse a YAML document string into a global config. */
let parseGlobal: string => result<globalConfig, string>

/** Parse a single hook command object (command + optional args). */
let parseHookCommand: JSON.t => option<hookCommand>

/** Parse a hooks config object (pre_generate, post_generate, timeout). */
let parseHooks: JSON.t => option<hooksConfig>

/** Parse a shell config object (enabled, tools, scripts, env). */
let parseShellConfig: JSON.t => option<shellConfig>

/** Merge project + global configs. Project values take precedence. */
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig

/** Validate a merged config for fail-fast enforcement. Returns Ok(()) or Error(message). */
let validateMergedConfig: mergedConfig => result<unit, string>

// --- Default constants (moved from ConfigParser -- WS4) ---

/** Default output directory for generated files. */
let defaultOutputDir: string

/** Default command timeout in seconds. */
let defaultTimeout: int