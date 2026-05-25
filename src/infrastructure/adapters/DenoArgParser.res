/**
 * Deno argument parser adapter implementing Ports.argParser.
 * Utilizing Deno's Node.js compatibility layer for util.parseArgs.
 */

type parseArgsOptions = {
  args: array<string>,
  strict: bool,
  allowPositionals: bool,
}

type parseArgsResult = {
  values: dict<JSON.t>,
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
        
        let keys = Dict.keysToArray(result.values)
        keys->Array.forEach(k => {
          let v = Dict.get(result.values, k)
          switch v {
          | Some(val) => {
              let t = Type.typeof(val)
              if t == #string {
                Dict.set(stringValues, k, Obj.magic(val))
              } else if t == #boolean {
                Dict.set(stringValues, k, Obj.magic(val) ? "true" : "false")
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
