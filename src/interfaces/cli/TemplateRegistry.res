let copyTemplateToRegistry: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~sourcePath: string,
  ~registryRoot: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
  ~force: bool,
  ~confirmOverwrite: string => promise<bool>,
) => promise<result<Config.globalConfig, string>> = async (
  ~deps,
  ~fs,
  ~path,
  ~name,
  ~sourcePath,
  ~registryRoot,
  ~configPath,
  ~globalConfig,
  ~force,
  ~confirmOverwrite,
) => {
  try {
    let sourceAbs = if deps.path.isAbsolute(sourcePath) {
      sourcePath
    } else {
      deps.path.resolve(deps.process.cwd(), sourcePath)
    }
    let targetPath = deps.path.join(registryRoot, name)
    let targetExists = await deps.fs.fileExists(targetPath)

    if targetExists && !force {
      let shouldOverwrite = await confirmOverwrite(targetPath)
      if !shouldOverwrite {
        Error("Copy cancelled by user")
      } else {
        let _ = await deps.fs.rm(targetPath, ~options={recursive: true})
        let _ = await deps.fs.mkdir(registryRoot, ~options={recursive: true})
        let _ = await deps.fs.cp(sourceAbs, targetPath, ~options={recursive: true})

        let withoutCurrent = globalConfig.registry->Array.filter(entry => entry.name != name)
        let updated: Config.globalConfig = {
          ...globalConfig,
          registry: withoutCurrent->Array.concat([{name, source: sourceAbs, path: targetPath}]),
        }
        let saveResult = await Config.saveGlobalAtPath(~fs, ~path, ~configPath, updated)
        switch saveResult {
        | Ok(()) => Ok(updated)
        | Error(e) => Error(e)
        }
      }
    } else {
      if targetExists {
        let _ = await deps.fs.rm(targetPath, ~options={recursive: true})
      }
      let _ = await deps.fs.mkdir(registryRoot, ~options={recursive: true})
      let _ = await deps.fs.cp(sourceAbs, targetPath, ~options={recursive: true})

      let withoutCurrent = globalConfig.registry->Array.filter(entry => entry.name != name)
      let updated: Config.globalConfig = {
        ...globalConfig,
        registry: withoutCurrent->Array.concat([{name, source: sourceAbs, path: targetPath}]),
      }
      let saveResult = await Config.saveGlobalAtPath(~fs, ~path, ~configPath, updated)
      switch saveResult {
      | Ok(()) => Ok(updated)
      | Error(e) => Error(e)
      }
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to copy template"
    }
    Error(msg)
  }
}

let removeTemplateFromRegistry: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
) => promise<result<Config.globalConfig, string>> = async (~deps, ~fs, ~path, ~name, ~configPath, ~globalConfig) => {
  let toRemove = globalConfig.registry->Array.find(entry => entry.name == name)
  switch toRemove {
  | None => Error("Template not found: " ++ name)
  | Some(entry) =>
    try {
      let exists = await deps.fs.fileExists(entry.path)
      if exists {
        let _ = await deps.fs.rm(entry.path, ~options={recursive: true})
      }
      let updated: Config.globalConfig = {
        ...globalConfig,
        registry: globalConfig.registry->Array.filter(src => src.name != name),
      }
      let saveResult = await Config.saveGlobalAtPath(~fs, ~path, ~configPath, updated)
      switch saveResult {
      | Ok(()) => Ok(updated)
      | Error(e) => Error(e)
      }
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Failed to remove template"
      }
      Error(msg)
    }
  }
}
