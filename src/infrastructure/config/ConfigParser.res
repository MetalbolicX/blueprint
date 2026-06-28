// ConfigParser — JSON/YAML parsing, merge, and validation logic
// Extracted from Config.res as part of T2 refactor

open ConfigTypes

let _parseTemplateSource: JSON.t => option<templateSource> = json => {
  switch json {
  | JSON.Object(dict) =>
    let parseStr = key => {
      switch Dict.get(dict, key) {
      | Some(JSON.String(s)) => Some(s)
      | _ => None
      }
    }
    switch (
      parseStr("name"),
      parseStr("source"),
      parseStr("path"),
    ) {
    | (Some(name), Some(source), Some(path)) => Some({name, source, path})
    | _ => None
    }
  | _ => None
  }
}

let _parseRegistry: JSON.t => array<templateSource> = json => {
  switch json {
  | JSON.Array(arr) => arr->Array.map(_parseTemplateSource)->Array.filterMap(x => x)
  | _ => []
  }
}

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

let _parseDictString: (dict<JSON.t>, string) => option<string> = (dict, key) => {
  switch Dict.get(dict, key) {
  | Some(JSON.String(s)) => Some(s)
  | _ => None
  }
}

let _parseDictInt: (dict<JSON.t>, string) => option<int> = (dict, key) => {
  switch Dict.get(dict, key) {
  | Some(JSON.Number(n)) => Some(Js.Math.floor(n))
  | _ => None
  }
}

let _parseDictBool: (dict<JSON.t>, string) => option<bool> = (dict, key) => {
  switch Dict.get(dict, key) {
  | Some(JSON.Boolean(b)) => Some(b)
  | _ => None
  }
}

let _parseTemplates: JSON.t => array<string> = json => {
  switch json {
  | JSON.Array(arr) => {
      let strings = arr->Array.map(item => {
        switch item {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      })
      strings->Array.filterMap(x => x)
    }
  | _ => []
  }
}

let _parseDefaultAttributes: JSON.t => dict<string> = json => {
  switch json {
  | JSON.Object(dict) => {
      let result = Dict.make()
      dict
      ->Dict.toArray
      ->Array.forEach(((key, value)) => {
        switch value {
        | JSON.String(s) => Dict.set(result, key, s)
        | _ => ()
        }
      })
      result
    }
  | _ => Dict.make()
  }
}

let parseGlobal: string => result<globalConfig, string> = yamlContent => {
  try {
    let json = ConfigYaml.parse(yamlContent)
    switch json {
    | JSON.Object(dict) => {
        let templates = switch Dict.get(dict, "templates") {
        | Some(v) => _parseTemplates(v)
        | None => []
        }
        let allowDangerousCommands = switch Dict.get(dict, "allow_dangerous_commands") {
        | Some(v) =>
          switch v {
          | JSON.Boolean(b) => b
          | _ => false
          }
        | None => false
        }
        let forceOverwrite = switch Dict.get(dict, "force_overwrite") {
        | Some(v) =>
          switch v {
          | JSON.Boolean(b) => b
          | _ => false
          }
        | None => false
        }
        let dryRun = switch Dict.get(dict, "dry_run") {
        | Some(v) =>
          switch v {
          | JSON.Boolean(b) => b
          | _ => false
          }
        | None => false
        }
        let timeout = switch Dict.get(dict, "timeout") {
        | Some(v) =>
          switch v {
          | JSON.Number(n) => Js.Math.floor(n)
          | _ => 5
          }
        | None => 5
        }
        let defaultAttributes = switch Dict.get(dict, "default_attributes") {
        | Some(v) => _parseDefaultAttributes(v)
        | None => Dict.make()
        }
        let registry = switch Dict.get(dict, "registry") {
        | Some(v) => _parseRegistry(v)
        | None => []
        }
        Ok({
          templates,
          allowDangerousCommands,
          forceOverwrite,
          dryRun,
          timeout,
          defaultAttributes,
          registry,
        })
      }
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

// Merge project + global configs. Project values take precedence.
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig = (
  ~global,
  ~project,
) => {
  let effectiveTimeout = switch project {
  | Some(p) =>
    switch p.hooks {
    | Some(h) =>
      switch h.timeout {
      | Some(t) => t
      | None => global.timeout
      }
    | None => global.timeout
    }
  | None => global.timeout
  }
  // Migration: allow_dangerous_commands: true → shell.enabled: true
  let effectiveShell = switch project {
  | Some(p) => p.shell
  | None => None
  }
  {
    templates: global.templates,
    allowDangerousCommands: global.allowDangerousCommands,
    forceOverwrite: global.forceOverwrite,
    dryRun: global.dryRun,
    timeout: effectiveTimeout,
    defaultAttributes: global.defaultAttributes,
    shell: ?effectiveShell,
  }
}

let parseHookCommand: JSON.t => option<hookCommand> = json => {
  switch json {
  | JSON.Object(dict) => {
      let command = switch Dict.get(dict, "command") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      | None => None
      }
      let args = switch Dict.get(dict, "args") {
      | Some(v) =>
        switch v {
        | JSON.Array(arr) => {
            let strings = arr->Array.map(item => {
              switch item {
              | JSON.String(s) => Some(s)
              | _ => None
              }
            })
            Some(strings->Array.filterMap(x => x))
          }
        | _ => None
        }
      | None => None
      }
      switch command {
      | Some(c) =>
        switch args {
        | Some(a) => Some({command: c, args: a})
        | None => Some({command: c})
        }
      | None => None
      }
    }
  | _ => None
  }
}

// Validate merged config for fail-fast enforcement
// Returns Ok if config is valid, Error(message) if not
let validateMergedConfig: mergedConfig => result<unit, string> = cfg => {
  if cfg.timeout < 1 {
    Error("timeout must be >= 1, got " ++ Int.toString(cfg.timeout))
  } else {
    switch cfg.shell {
    | Some(s) if s.enabled && s.tools->Option.isNone =>
      Error("shell.enabled=true requires tools to be defined")
    | _ => Ok()
    }
  }
}

let parseHooks: JSON.t => option<hooksConfig> = json => {
  switch json {
  | JSON.Object(dict) => {
      let preGenerate: option<hookCommand> = switch Dict.get(dict, "pre_generate") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some({command: s}) // Legacy: simple string mapped to command
        | _ => parseHookCommand(v)
        }
      | None => None
      }

      let postGenerate: option<hookCommand> = switch Dict.get(dict, "post_generate") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some({command: s}) // Legacy: simple string mapped to command
        | _ => parseHookCommand(v)
        }
      | None => None
      }

      let timeout = switch Dict.get(dict, "timeout") {
      | Some(v) =>
        switch v {
        | JSON.Number(n) => Some(Js.Math.floor(n))
        | _ => None
        }
      | None => None
      }

      if preGenerate == None && postGenerate == None && timeout == None {
        None
      } else {
        Some({preGenerate: ?preGenerate, postGenerate: ?postGenerate, timeout: ?timeout})
      }
    }
  | _ => None
  }
}

let parseShellTool: JSON.t => option<shellTool> = json => {
  switch json {
  | JSON.Object(dict) => {
      let name = switch Dict.get(dict, "name") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      | None => None
      }
      let command = switch Dict.get(dict, "command") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      | None => None
      }
      let args = switch Dict.get(dict, "args") {
      | Some(v) =>
        switch v {
        | JSON.Array(arr) => {
            let strings = arr->Array.map(item => {
              switch item {
              | JSON.String(s) => Some(s)
              | _ => None
              }
            })
            Some(strings->Array.filterMap(x => x))
          }
        | _ => None
        }
      | None => None
      }
      switch (name, command) {
      | (Some(n), Some(c)) => Some({name: n, command: c, args: ?args})
      | _ => None
      }
    }
  | _ => None
  }
}

let parseScriptDef: JSON.t => option<scriptDef> = json => {
  switch json {
  | JSON.Object(dict) => {
      let name = switch Dict.get(dict, "name") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      | None => None
      }
      let path = switch Dict.get(dict, "path") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      | None => None
      }
      let args = switch Dict.get(dict, "args") {
      | Some(v) =>
        switch v {
        | JSON.Array(arr) => {
            let strings = arr->Array.map(item => {
              switch item {
              | JSON.String(s) => Some(s)
              | _ => None
              }
            })
            Some(strings->Array.filterMap(x => x))
          }
        | _ => None
        }
      | None => None
      }
      switch (name, path) {
      | (Some(n), Some(p)) => Some({name: n, path: p, args: ?args})
      | _ => None
      }
    }
  | _ => None
  }
}

let parseShellEnv: JSON.t => option<shellEnv> = json => {
  switch json {
  | JSON.Object(dict) => {
      let result: shellEnv = {vars: Dict.make()}
      dict
      ->Dict.toArray
      ->Array.forEach(((key, value)) => {
        switch value {
        | JSON.String(s) => Dict.set(result.vars, key, s)
        | _ => ()
        }
      })
      if Dict.size(result.vars) > 0 {
        Some(result)
      } else {
        None
      }
    }
  | _ => None
  }
}

let parseShellConfig: JSON.t => option<shellConfig> = json => {
  switch json {
  | JSON.Object(dict) => {
      let enabled = switch Dict.get(dict, "enabled") {
      | Some(v) =>
        switch v {
        | JSON.Boolean(b) => b
        | _ => false
        }
      | None => false
      }
      let tools = switch Dict.get(dict, "tools") {
      | Some(v) =>
        switch v {
        | JSON.Array(arr) => {
            let parsed = arr->Array.map(parseShellTool)->Array.filterMap(x => x)
            if Array.length(parsed) > 0 {
              Some(parsed)
            } else {
              None
            }
          }
        | _ => None
        }
      | None => None
      }
      let env = switch Dict.get(dict, "env") {
      | Some(v) => parseShellEnv(v)
      | None => None
      }
      let scripts = switch Dict.get(dict, "scripts") {
      | Some(v) =>
        switch v {
        | JSON.Array(arr) => {
            let parsed = arr->Array.map(parseScriptDef)->Array.filterMap(x => x)
            if Array.length(parsed) > 0 {
              Some(parsed)
            } else {
              None
            }
          }
        | _ => None
        }
      | None => None
      }
      Some({enabled, tools: ?tools, scripts: ?scripts, env: ?env})
    }
  | _ => None
  }
}

let parse: string => result<config, string> = yamlContent => {
  try {
    let json = ConfigYaml.parse(yamlContent)

    switch json {
    | JSON.Object(dict) => {
        let hooks = switch Dict.get(dict, "hooks") {
        | Some(v) => parseHooks(v)
        | None => None
        }

        let output = switch Dict.get(dict, "output") {
        | Some(v) =>
          switch v {
          | JSON.String(s) => Some(s)
          | _ => None
          }
        | None => None
        }

        let shell = switch Dict.get(dict, "shell") {
        | Some(v) => parseShellConfig(v)
        | None => None
        }

        Ok({hooks: ?hooks, output: ?output, shell: ?shell})
      }
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

// Default config values
let defaultOutputDir: string = "generated"
let defaultTimeout: int = 5 // seconds

// Export for ConfigStore — converts globalConfig to YAML string
let _globalConfigToYamlExport: globalConfig => string = cfg => {
  ConfigYaml.stringify(JSON.Object(_globalConfigToYamlObject(cfg)))
}