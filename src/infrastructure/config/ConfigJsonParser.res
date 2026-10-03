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

let timeoutDurationRegex: RegExp.t = /^([0-9]+)(s|m)$/
let bareTimeoutRegex: RegExp.t = /^[0-9]+$/

@val external numberIsFinite: float => bool = "Number.isFinite"
@val external numberIsInteger: float => bool = "Number.isInteger"

let parseTimeout: JSON.t => result<int, string> = value => {
  switch value {
  | JSON.Number(n) =>
    if !numberIsFinite(n) || !numberIsInteger(n) {
      Error("hooks.timeout must be a finite integer >= 1, got number")
    } else if n < 1. {
      Error("timeout must be >= 1, got " ++ Int.toString(Js.Math.floor(n)))
    } else {
      Ok(Js.Math.floor(n))
    }
  | JSON.String(s) =>
    switch Js.String.match_(timeoutDurationRegex, s) {
    | Some(parts) => {
        let amountOpt: option<string> = Obj.magic(parts[1])
        let unitOpt: option<string> = Obj.magic(parts[2])
        switch (amountOpt, unitOpt) {
        | (Some(amount), Some(unit)) =>
          switch Int.fromString(amount) {
          | Some(n) => {
              let seconds = unit === "m" ? n * 60 : n
              if seconds >= 1 {
                Ok(seconds)
              } else {
                Error("hooks.timeout must be >= 1, got " ++ s)
              }
            }
          | None => Error("hooks.timeout must be a duration string with a finite integer value, got string")
          }
        | _ => Error("hooks.timeout must be a duration string, got string")
        }
      }
    | None if RegExp.test(bareTimeoutRegex, s) =>
      Error("hooks.timeout " ++ s ++ " is ambiguous; add a unit (s or m)")
    | None => Error("hooks.timeout must be a duration string such as 30s or 5m, got string")
    }
  | JSON.Boolean(_) => Error("hooks.timeout must be a duration string or integer seconds, got boolean")
  | JSON.Object(_) => Error("hooks.timeout must be a duration string or integer seconds, got object")
  | JSON.Array(_) => Error("hooks.timeout must be a duration string or integer seconds, got array")
  | JSON.Null => Error("hooks.timeout must be a duration string or integer seconds, got null")
  }
}

let parseHooksResult: JSON.t => result<option<hooksConfig>, string> = json => {
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
    let timeoutResult = switch Dict.get(dict, "timeout") {
    | None => Ok(None)
    | Some(value) => parseTimeout(value)->Result.map(timeout => Some(timeout))
    }

    switch timeoutResult {
    | Error(message) => Error(message)
    | Ok(timeout) =>
      if preGenerate->Option.isNone && postGenerate->Option.isNone && timeout->Option.isNone {
        Ok(None)
      } else {
        Ok(Some({preGenerate: ?preGenerate, postGenerate: ?postGenerate, timeout: ?timeout}))
      }
    }
  | _ => Ok(None)
  }
}

let parseHooks: JSON.t => option<hooksConfig> = json =>
  switch parseHooksResult(json) {
  | Ok(hooks) => hooks
  | Error(_) => None
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
