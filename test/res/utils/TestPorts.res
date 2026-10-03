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
 * An ejs stub that delegates to the real Bindings.Ejs.render.
 * Use this in tests that need real EJS template interpolation.
 */
let stubEjs: ejs = {
  renderString: (~template, ~context) => {
    try {
      Ok(Bindings.Ejs.render(template, context->Obj.magic))
    } catch {
    | JsExn(obj) => {
        let msg = switch JsExn.message(obj) {
        | Some(m) => m
        | None => "EJS render error"
        }
        Error(msg)
      }
    }
  },
  renderFile: (~path as _path, ~context as _context) => Promise.resolve(Error("stubEjs.renderFile not implemented in TestPorts")),
}

let stubFetcher: fetcher = {
  fetch: _url => Promise.resolve(Error("stubFetcher.fetch not implemented in TestPorts")),
  clearCache: () => (),
}

let stubPathSecurity: pathSecurity = {
  isWithinTree: (candidate, root, path, fs) => PathSecurity.isWithinTree(candidate, root, path, fs),
}

let stubShellBuilder: shellBuilder = {
  buildEnvFilterConfig: shellEnv => {
    let config = ShellBuilder.buildEnvFilterConfig(shellEnv)
    {vars: config.vars->Array.map(entry => ({key: entry.key, value: entry.value} :> Ports.shellEnvEntry))}
  },
}

let stubEnvFilter: envFilter = {
  buildSafeEnv: (config, inheritedEnv) => NodeJsEnvFilter.make().buildSafeEnv(config, inheritedEnv),
}

let stubHooks: hooks = {run: Hooks.run}
