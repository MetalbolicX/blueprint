// ConfigStore — I/O operations for config loading and saving
// Extracted from Config.res as part of T2 refactor

open ConfigTypes

// Resolve XDG-style global config path: ~/.config/blueprint/config.yaml
let _globalConfigPath: (string, Ports.path) => string = (homeDir, path) => {
  path.join(path.join(path.join(homeDir, ".config"), "blueprint"), "config.yaml")
}

let saveGlobalAtPath: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~configPath: string,
  globalConfig,
) => promise<result<unit, string>> = async (
  ~fs,
  ~path,
  ~configPath,
  cfg,
) => {
  try {
    let configDir = path.dirname(configPath)
    let dirExists = await fs.fileExists(configDir)
    if !dirExists {
      let _ = await fs.mkdir(configDir, ~options={recursive: true})
    }
    let yaml = ConfigYaml.serializeGlobalConfig(cfg)
    let _ = await fs.writeFile(configPath, yaml)
    Ok(())
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to save global config"
    }
    Error(msg)
  }
}

let saveGlobal: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~homeDir: string,
  globalConfig,
) => promise<result<unit, string>> = async (~fs, ~path, ~homeDir, cfg) => {
  let configPath = _globalConfigPath(homeDir, path)
  await saveGlobalAtPath(~fs, ~path, ~configPath, cfg)
}

let loadGlobal: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~homeDir: string,
) => promise<result<option<globalConfig>, string>> = async (
  ~fs,
  ~path,
  ~homeDir,
) => {
  let configPath = _globalConfigPath(homeDir, path)

  let exists = await fs.fileExists(configPath)
  if !exists {
    Ok(None)
  } else {
    try {
      let content = await fs.readFile(configPath, ~options={encoding: "utf8"})
      let result = ConfigYaml.parseGlobal(content)
      switch result {
      | Ok(cfg) => Ok(Some(cfg))
      | Error(e) => Error(e)
      }
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Failed to read global config"
      }
      Error(msg)
    }
  }
}

let loadMergedGlobalConfig: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~homeDir: string,
) => promise<globalConfig> = async (~fs, ~path, ~homeDir) => {
  let globalConfigResult = await loadGlobal(~fs, ~path, ~homeDir)
  switch globalConfigResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => defaultGlobalConfig
  | Error(e) =>
    Console.warn("Warning: could not load global config, using default. Reason: " ++ e)
    defaultGlobalConfig
  }
}

// Load .blueprint.yaml from a given directory
let loadFrom: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  string,
) => promise<result<option<config>, string>> = async (~fs, ~path, dir) => {
  let configPath = path.join(dir, ".blueprint.yaml")

  let exists = await fs.fileExists(configPath)
  if !exists {
    Ok(None)
  } else {
    try {
      let content = await fs.readFile(configPath, ~options={encoding: "utf8"})
      let result = ConfigYaml.parse(content)
      switch result {
      | Ok(cfg) => Ok(Some(cfg))
      | Error(e) => Error(e)
      }
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Failed to read config"
      }
      Error(msg)
    }
  }
}