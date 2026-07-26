/**
 * NodeJsYamlParser — Node.js yaml adapter implementing Ports.yamlParser.
 */

open Ports

let make: unit => yamlParser = () => {
  parse: yamlString => {
    try {
      Ok(Bindings.Yaml.parse(yamlString))
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "YAML parse error"
      }
      Error(msg)
    }
  },
}
