// Config parsing — load and parse .fluxo.yaml hooks config
// Mirrors Go version's Config struct

type hooksConfig = {
  preGenerate: option<string>,
  postGenerate: option<string>,
  timeout: option<int>,
}

type config = {
  hooks: option<hooksConfig>,
  output: option<string>,
}

let parseHooks: Js.Json.t => option<hooksConfig> = json => {
  switch Js.Json.classify(json) {
  | Js.Json.JObject(dict) => {
    let preGenerate = switch Js.Dict.get(dict, "pre_generate") {
    | Some(v) =>
      switch Js.Json.classify(v) {
      | Js.Json.JString(s) => Some(s)
      | _ => None
      }
    | None => None
    }

    let postGenerate = switch Js.Dict.get(dict, "post_generate") {
    | Some(v) =>
      switch Js.Json.classify(v) {
      | Js.Json.JString(s) => Some(s)
      | _ => None
      }
    | None => None
    }

    let timeout = switch Js.Dict.get(dict, "timeout") {
    | Some(v) =>
      switch Js.Json.classify(v) {
      | Js.Json.JNumber(n) => Some(Js.Math.floor(n))
      | _ => None
      }
    | None => None
    }

    if preGenerate == None && postGenerate == None && timeout == None {
      None
    } else {
      Some({ preGenerate: preGenerate, postGenerate: postGenerate, timeout: timeout })
    }
  }
  | _ => None
}

let parse: string => result<config, string> = yamlContent => {
  try {
    let json = Bindings.Yaml.parse(yamlContent)

    switch Js.Json.classify(json) {
    | Js.Json.JObject(dict) => {
      let hooks = switch Js.Dict.get(dict, "hooks") {
      | Some(v) => parseHooks(v)
      | None => None
      }

      let output = switch Js.Dict.get(dict, "output") {
      | Some(v) =>
        switch Js.Json.classify(v) {
        | Js.Json.JString(s) => Some(s)
        | _ => None
        }
      | None => None
      }

      Ok({ hooks: hooks, output: output })
    }
    | _ => Ok({ hooks: None, output: None })
    }
  } catch {
  | Js.Exn.Error(obj) =>
    let msg = switch Js.Exn.message(obj) {
    | Some(m) => m
    | None => "Failed to parse config"
    }
    Error(msg)
  }
}

// Load .fluxo.yaml from a given directory
let loadFrom: string => promise<result<option<config>, string>> = async dir => {
  let configPath = Node.Path.join(dir, ".fluxo.yaml")

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
    | Js.Exn.Error(obj) =>
      let msg = switch Js.Exn.message(obj) {
      | Some(m) => m
      | None => "Failed to read config"
      }
      Error(msg)
    }
  }
}

// Default config values
let defaultOutputDir: string = "generated"
let defaultTimeout: int = 5  // seconds