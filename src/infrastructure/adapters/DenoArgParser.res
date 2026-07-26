/**
 * DenoArgParser — Deno argument parser adapter implementing Ports.argParser.
 * Delegates to ArgParserShared for shared parsing logic.
 */

open ArgParserShared

let make: unit => Ports.argParser = () => {
  {
    parse: (~args, ~strict: bool, ~allowPositionals: bool) => {
      let options: dict<parseArgOption> = {
        let opts = Dict.make()
        Dict.set(opts, "name", {kind: "string"})
        Dict.set(opts, "output", {kind: "string"})
        Dict.set(opts, "force", {kind: "boolean"})
        opts
      }
      parse(~args, ~strict, ~allowPositionals, ~options)
    }
  }
}
