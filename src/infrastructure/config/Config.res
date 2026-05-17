// Config parsing — load and parse .fluxo.yaml hooks config
// Mirrors Go version's Config struct

type hooksConfig = {
  preGenerate?: string,
  postGenerate?: string,
  timeout?: int,
}

type config = {
  hooks?: hooksConfig,
  output?: string,
}

let parseHooks: JSON.t => option<hooksConfig> = json => {
  switch json {
  | JSON.Object(dict) => {
      let preGenerate = switch Dict.get(dict, "pre_generate") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      | None => None
      }

      let postGenerate = switch Dict.get(dict, "post_generate") {
      | Some(v) =>
        switch v {
        | JSON.String(s) => Some(s)
        | _ => None
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

let parse: string => result<config, string> = yamlContent => {
  try {
    let json = Bindings.Yaml.parse(yamlContent)

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

        Ok({hooks: ?hooks, output: ?output})
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

// Load .fluxo.yaml from a given directory
let loadFrom: string => promise<result<option<config>, string>> = async dir => {
  let configPath = Bindings.Path.join(dir, ".fluxo.yaml")

  let exists = await Bindings.Fs.fileExists(configPath)
  if !exists {
    Ok(None)
  } else {
    try {
      let content = await Bindings.Fs.readFile(configPath, ~options={encoding: "utf8"})
      let result = parse(content)
      switch result {
      | Ok(cfg) => Ok(Some(cfg))
      | Error(e) => Error(e)
      }
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Failed to read config"
      }
      Error(msg)
    }
  }
}

// Default config values
let defaultOutputDir: string = "generated"
let defaultTimeout: int = 5 // seconds
