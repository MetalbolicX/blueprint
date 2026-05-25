type parseArgsOptions = {
  args: array<string>,
  strict: bool,
  allowPositionals: bool,
}

type parseArgsResult = {
  values: dict<Js.Json.t>,
  positionals: array<string>,
}

@module("node:util")
external parseArgsRaw: parseArgsOptions => parseArgsResult = "parseArgs"

let make: unit => Ports.argParser = () => {
  {
    parse: (~args, ~strict: bool, ~allowPositionals: bool) => {
      try {
        let result = parseArgsRaw({
          args,
          strict,
          allowPositionals,
        })
        
        let stringValues = Dict.make()
        
        // Convert JS values to string
        let keys = Dict.keysToArray(result.values)
        keys->Array.forEach(k => {
          let v = Dict.get(result.values, k)
          switch v {
          | Some(val) => {
              let t = Js.Types.classify(val)
              switch t {
              | JSString(s) => Dict.set(stringValues, k, s)
              | JSTrue => Dict.set(stringValues, k, "true")
              | JSFalse => Dict.set(stringValues, k, "false")
              | _ => ()
              }
            }
          | None => ()
          }
        })
        
        Ok({
          Ports.values: stringValues,
          positionals: result.positionals,
        })
      } catch {
      | JsExn(e) => {
          let msg = switch JsExn.message(e->Obj.magic) {
          | Some(m) => m
          | None => "unknown error"
          }
          Error(msg)
        }
      | _ => Error("unknown parse error")
      }
    }
  }
}
