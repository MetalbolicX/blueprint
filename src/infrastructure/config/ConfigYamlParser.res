// ConfigYamlParser.res
open ConfigTypes

let parseGlobal: string => result<globalConfig, string> = yamlContent => {
  try {
    let json = ConfigYamlBindings.parse(yamlContent)
    switch json {
    | JSON.Object(dict) =>
      let templates = switch Dict.get(dict, "templates") {
      | Some(v) => ConfigJsonParser.parseTemplates(v)
      | None => []
      }
      let forceOverwrite = switch Dict.get(dict, "force_overwrite") {
      | Some(JSON.Boolean(b)) => b
      | _ => false
      }
      let dryRun = switch Dict.get(dict, "dry_run") {
      | Some(JSON.Boolean(b)) => b
      | _ => false
      }
      let timeout = switch Dict.get(dict, "timeout") {
      | Some(JSON.Number(n)) => Js.Math.floor(n)
      | _ => 5
      }
      let defaultAttributes = switch Dict.get(dict, "default_attributes") {
      | Some(v) => ConfigJsonParser.parseDefaultAttributes(v)
      | None => Dict.make()
      }
      let registry = switch Dict.get(dict, "registry") {
      | Some(v) => ConfigJsonParser.parseRegistry(v)
      | None => []
      }
      Ok({
        templates,
        forceOverwrite,
        dryRun,
        timeout,
        defaultAttributes,
        registry,
      })
    | _ => Ok(defaultGlobalConfig)
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to parse global config"
    }
    Error(msg)
  }
}

let parseConfig: string => result<config, string> = yamlContent => {
  try {
    let json = ConfigYamlBindings.parse(yamlContent)

    switch json {
    | JSON.Object(dict) =>
      let hooks = Dict.get(dict, "hooks")->Option.flatMap(ConfigJsonParser.parseHooks)
      let output = switch Dict.get(dict, "output") {
      | Some(JSON.String(s)) => Some(s)
      | _ => None
      }
      let dryRun = switch Dict.get(dict, "dry_run") {
      | Some(JSON.Boolean(b)) => Some(b)
      | _ => None
      }
      let shell = Dict.get(dict, "shell")->Option.flatMap(ConfigJsonParser.parseShellConfig)

      Ok({hooks: ?hooks, output: ?output, dryRun: ?dryRun, shell: ?shell})
    | _ => Ok({})
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to parse config"
    }
    Error(msg)
  }
}
