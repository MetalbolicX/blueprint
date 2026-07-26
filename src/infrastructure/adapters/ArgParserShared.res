/**
 * ArgParserShared — runtime-agnostic argument parsing logic.
 * Shared between NodeJsArgParser and DenoArgParser adapters.
 * Takes raw argv array + option definitions, returns parsed result.
 */

type parseArgOption = {
  @as("type") kind: string,
  short?: string,
}

type parseArgsOptions = {
  args: array<string>,
  strict: bool,
  allowPositionals: bool,
  options?: dict<parseArgOption>,
}

type parseArgsResult = {
  values: dict<JSON.t>,
  positionals: array<string>,
}

@module("node:util")
external parseArgsRaw: parseArgsOptions => parseArgsResult = "parseArgs"

let convertValues = (jsonValues: dict<JSON.t>): dict<string> => {
  let stringValues = Dict.make()
  let keys = Dict.keysToArray(jsonValues)
  keys->Array.forEach(k => {
    let v = Dict.get(jsonValues, k)
    switch v {
    | Some(val) => {
        switch val {
        | String(s) => Dict.set(stringValues, k, s)
        | Boolean(true) => Dict.set(stringValues, k, "true")
        | Boolean(false) => Dict.set(stringValues, k, "false")
        | _ => ()
        }
      }
    | None => ()
    }
  })
  stringValues
}

let parse = (
  ~args: array<string>,
  ~strict: bool,
  ~allowPositionals: bool,
  ~options: dict<parseArgOption>,
): result<Ports.parsedArgs, string> => {
  try {
    let result = parseArgsRaw({
      options: options,
      args,
      strict,
      allowPositionals,
    })

    let stringValues = convertValues(result.values)

    Ok({
      Ports.values: stringValues,
      positionals: result.positionals,
    })
  } catch {
  | JsExn(e) => {
      let msg = switch JsExn.message(e) {
      | Some(m) => m
      | None => "unknown error"
      }
      Error(msg)
    }
  | _ => Error("unknown parse error")
  }
}
