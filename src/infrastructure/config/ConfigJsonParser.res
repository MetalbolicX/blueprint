// ConfigJsonParser.res
open ConfigTypes

let getStringField = (dict: Dict.t<JSON.t>, key: string): option<string> => {
  switch dict->Dict.get(key) {
  | Some(JSON.String(s)) => Some(s)
  | _ => None
  }
}

let _getObjectField = (dict: Dict.t<JSON.t>, key: string): option<Dict.t<JSON.t>> => {
  switch dict->Dict.get(key) {
  | Some(JSON.Object(o)) => Some(o)
  | _ => None
  }
}

let _getIntField = (dict: Dict.t<JSON.t>, key: string, ~default: int): int => {
  switch dict->Dict.get(key) {
  | Some(JSON.Number(n)) => n->Float.toInt
  | _ => default
  }
}

let getBoolField = (dict: Dict.t<JSON.t>, key: string, ~default: bool): bool => {
  switch dict->Dict.get(key) {
  | Some(JSON.Boolean(b)) => b
  | _ => default
  }
}

let parseStringArray: JSON.t => option<array<string>> = json => {
  switch json {
  | JSON.Array(arr) =>
    Some(
      arr
      ->Array.map(item =>
        switch item {
        | JSON.String(s) => Some(s)
        | _ => None
        }
      )
      ->Array.filterMap(x => x),
    )
  | _ => None
  }
}

let parseTemplateSource: JSON.t => option<templateSource> = json => {
  switch json {
  | JSON.Object(dict) =>
    switch (getStringField(dict, "name"), getStringField(dict, "source"), getStringField(dict, "path")) {
    | (Some(name), Some(source), Some(path)) => Some({name, source, path})
    | _ => None
    }
  | _ => None
  }
}

let parseRegistry: JSON.t => array<templateSource> = json => {
  switch json {
  | JSON.Array(arr) => arr->Array.map(parseTemplateSource)->Array.filterMap(x => x)
  | _ => []
  }
}

let parseTemplates: JSON.t => array<string> = json => {
  switch json {
  | JSON.Array(arr) =>
    let strings = arr->Array.map(item => {
      switch item {
      | JSON.String(s) => Some(s)
      | _ => None
      }
    })
    strings->Array.filterMap(x => x)
  | _ => []
  }
}

let parseDefaultAttributes: JSON.t => dict<string> = json => {
  switch json {
  | JSON.Object(dict) =>
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
  | _ => Dict.make()
  }
}

let parseHookCommand: JSON.t => option<hookCommand> = json => {
  switch json {
  | JSON.Object(dict) =>
    let command = getStringField(dict, "command")
    let args = Dict.get(dict, "args")->Option.flatMap(parseStringArray)

    command->Option.map(c => {command: c, args: ?args})
  | _ => None
  }
}

let parseHooks: JSON.t => option<hooksConfig> = json => {
  switch json {
  | JSON.Object(dict) =>
    let preGenerate =
      Dict.get(dict, "pre_generate")->Option.flatMap(v =>
        switch v {
        | JSON.String(s) => Some({command: s})
        | _ => parseHookCommand(v)
        }
      )
    let postGenerate =
      Dict.get(dict, "post_generate")->Option.flatMap(v =>
        switch v {
        | JSON.String(s) => Some({command: s})
        | _ => parseHookCommand(v)
        }
      )
    let timeout =
      Dict.get(dict, "timeout")->Option.flatMap(v =>
        switch v {
        | JSON.Number(n) => Some(Js.Math.floor(n))
        | _ => None
        }
      )

    if preGenerate->Option.isNone && postGenerate->Option.isNone && timeout->Option.isNone {
      None
    } else {
      Some({preGenerate: ?preGenerate, postGenerate: ?postGenerate, timeout: ?timeout})
    }
  | _ => None
  }
}

let parseShellTool: JSON.t => option<shellTool> = json => {
  switch json {
  | JSON.Object(dict) =>
    let name = getStringField(dict, "name")
    let command = getStringField(dict, "command")
    let args = Dict.get(dict, "args")->Option.flatMap(parseStringArray)

    switch (name, command) {
    | (Some(n), Some(c)) => Some({name: n, command: c, args: ?args})
    | _ => None
    }
  | _ => None
  }
}

let parseScriptDef: JSON.t => option<scriptDef> = json => {
  switch json {
  | JSON.Object(dict) =>
    let name = getStringField(dict, "name")
    let path = getStringField(dict, "path")
    let args = Dict.get(dict, "args")->Option.flatMap(parseStringArray)

    switch (name, path) {
    | (Some(n), Some(p)) => Some({name: n, path: p, args: ?args})
    | _ => None
    }
  | _ => None
  }
}

let parseShellEnv: JSON.t => option<shellEnv> = json => {
  switch json {
  | JSON.Object(dict) =>
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
  | _ => None
  }
}

let parseShellConfig: JSON.t => option<shellConfig> = json => {
  switch json {
  | JSON.Object(dict) =>
    let enabled = getBoolField(dict, "enabled", ~default=false)
    let tools =
      Dict.get(dict, "tools")
      ->Option.flatMap(v =>
        switch v {
        | JSON.Array(arr) =>
          let parsed = arr->Array.map(parseShellTool)->Array.filterMap(x => x)
          Array.length(parsed) > 0 ? Some(parsed) : None
        | _ => None
        }
      )
    let env = Dict.get(dict, "env")->Option.flatMap(parseShellEnv)
    let scripts =
      Dict.get(dict, "scripts")
      ->Option.flatMap(v =>
        switch v {
        | JSON.Array(arr) =>
          let parsed = arr->Array.map(parseScriptDef)->Array.filterMap(x => x)
          Array.length(parsed) > 0 ? Some(parsed) : None
        | _ => None
        }
      )
    Some({enabled, tools: ?tools, scripts: ?scripts, env: ?env})
  | _ => None
  }
}
