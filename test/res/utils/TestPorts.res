/**
 * TestPorts — shared test port stubs for unit testing.
 */

open Ports

/**
 * A yamlParser stub that delegates to the real Bindings.Yaml.parse.
 * Use this in tests that need Manifest.parse without full Ports.deps wiring.
 */
let stubYamlParser: yamlParser = {
  parse: s => {
    try {
      Ok(Bindings.Yaml.parse(s))
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

/**
 * A minimal ejs stub for tests.
 */
let stubEjs: ejs = {
  renderString: (~template, ~context as _context) => Ok(template),
  renderFile: (~path, ~context as _context) => Promise.resolve(Ok("rendered: " ++ path)),
}
