// ConfigYaml -- YAML binding adapter for the config subsystem.
// Single owner of the YAML binding layer (WS2 extraction from ConfigParser).
// Also owns globalConfig -> YAML serialization (WS3 extraction from ConfigParser).

open ConfigTypes

let parse: string => JSON.t = Bindings.Yaml.parse
let stringify: JSON.t => string = Bindings.Yaml.stringify

// --- Serialization helpers (moved from ConfigParser -- WS3) ---
let _templateSourceToYamlEntry: templateSource => dict<JSON.t> = src => {
  let entry = Dict.make()
  Dict.set(entry, "name", JSON.String(src.name))
  Dict.set(entry, "source", JSON.String(src.source))
  Dict.set(entry, "path", JSON.String(src.path))
  entry
}

let _defaultAttributesToJson: dict<string> => dict<JSON.t> = attrs => {
  let out = Dict.make()
  attrs->Dict.toArray->Array.forEach(((k, v)) => Dict.set(out, k, JSON.String(v)))
  out
}

let _globalConfigToYamlObject: globalConfig => dict<JSON.t> = cfg => {
  let root = Dict.make()
  Dict.set(root, "templates", JSON.Array(cfg.templates->Array.map(s => JSON.String(s))))
  Dict.set(root, "allow_dangerous_commands", JSON.Boolean(cfg.allowDangerousCommands))
  Dict.set(root, "force_overwrite", JSON.Boolean(cfg.forceOverwrite))
  Dict.set(root, "dry_run", JSON.Boolean(cfg.dryRun))
  Dict.set(root, "timeout", JSON.Number(Int.toFloat(cfg.timeout)))
  Dict.set(root, "default_attributes", JSON.Object(_defaultAttributesToJson(cfg.defaultAttributes)))
  Dict.set(
    root,
    "registry",
    JSON.Array(cfg.registry->Array.map(src => JSON.Object(_templateSourceToYamlEntry(src)))),
  )
  root
}

let serializeGlobalConfig: globalConfig => string = cfg => {
  stringify(JSON.Object(_globalConfigToYamlObject(cfg)))
}