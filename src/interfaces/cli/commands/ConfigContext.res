// ConfigContext — shared config-loading prelude extracted from the 4 functions
// that duplicate the same ~deps/~fs/~path config-acquisition pattern.
//
// Usage: call `loadConfigContext(~deps, ~fs, ~path)` to get homeDir, globalConfig,
// projectConfig, and merged ready. Discovery is NOT included — callers that need
// generators should call Discovery.discover separately, AFTER validation
// (the runGenerate test asserts that invalid config exits before discovery runs).

type t = {
  homeDir: string,
  globalConfig: Config.globalConfig,
  projectConfig: option<Config.config>,
  merged: Config.mergedConfig,
}

let loadConfigContext: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<t> = async (~deps, ~fs, ~path) => {
  let homeDir = deps.process.homedir()
  let globalConfig = await Config.loadMergedGlobalConfig(~fs, ~path, ~homeDir)
  let cwd = deps.process.cwd()
  let configResult = await Config.loadFrom(~fs, ~path, cwd)
  let projectConfig = switch configResult {
  | Ok(c) => c
  | Error(_) => None
  }
  let merged = Config.mergeConfig(~global=globalConfig, ~project=projectConfig)
  {homeDir, globalConfig, projectConfig, merged}
}
