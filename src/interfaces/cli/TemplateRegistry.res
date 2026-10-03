let rec walkInstallSource: (
  ~source: string,
  ~entry: string,
  ~depth: int,
  ~isRoot: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~entryCount: ref<int>,
) => promise<result<unit, string>> = async (
  ~source,
  ~entry,
  ~depth,
  ~isRoot,
  ~fs,
  ~path,
  ~entryCount,
) => {
  let symlinkError = "Refusing to install " ++ source ++ ": symbolic links are not allowed in templates"
  if depth > 32 {
    Error("Refusing to install " ++ source ++ ": template tree exceeds depth cap (32)")
  } else {
    let metadata = await fs.lstat(entry)
    if metadata.isSymbolicLink() {
      Error(symlinkError)
    } else if isRoot && !(await fs.stat(source)).isDirectory() {
      Error("Refusing to install " ++ source ++ ": source is not a directory")
    } else if metadata.isDirectory() {
      let names = await fs.readdir(entry)
      if isRoot && names->Array.includes(".blueprint-provenance") {
        Error("Refusing to install " ++ source ++ ": source already contains a .blueprint-provenance marker")
      } else {
        let rec visit: int => promise<result<unit, string>> = async index => {
          if index >= Array.length(names) {
            Ok(())
          } else {
            entryCount := entryCount.contents + 1
            if entryCount.contents > 10000 {
              Error("Refusing to install " ++ source ++ ": template tree exceeds entry cap (10000)")
            } else {
              let name = switch names[index] {
              | Some(name) => name
              | None => ""
              }
              switch await walkInstallSource(
                ~source,
                ~entry=path.join(entry, name),
                ~depth=depth + 1,
                ~isRoot=false,
                ~fs,
                ~path,
                ~entryCount,
              ) {
              | Error(message) => Error(message)
              | Ok(()) => await visit(index + 1)
              }
            }
          }
        }
        await visit(0)
      }
    } else {
      Ok(())
    }
  }
}

let validateSourceForInstall: (~source: string, ~fs: Ports.fileSystem, ~path: Ports.path) => promise<result<unit, string>> = async (~source, ~fs, ~path) => {
  try {
    await walkInstallSource(~source, ~entry=source, ~depth=0, ~isRoot=true, ~fs, ~path, ~entryCount=ref(0))
  } catch {
  | _ => Error("Refusing to install " ++ source ++ ": unable to inspect source tree")
  }
}

type markerCheck =
  | MarkerAbsent
  | MarkerPresent
  | MarkerInspectFailed(string)

let removeCopiedMarkerIfPresent: (~fs: Ports.fileSystem, ~targetPath: string, ~markerPath: string) => promise<markerCheck> = async (~fs, ~targetPath, ~markerPath) => {
  let inspection = try {
    let _ = await fs.lstat(markerPath)
    MarkerPresent
  } catch {
  | JsExn(obj) =>
    let code = switch Obj.magic(obj)["code"] {
    | Some(code) => code
    | None => ""
    }
    if code == "ENOENT" || code == "ENOTDIR" {
      MarkerAbsent
    } else {
      MarkerInspectFailed("unable to verify marker absence after copy")
    }
  | _ => MarkerInspectFailed("unable to verify marker absence after copy")
  }
  switch inspection {
  | MarkerAbsent => MarkerAbsent
  | MarkerInspectFailed(reason) => MarkerInspectFailed(reason)
  | MarkerPresent =>
    // A marker that genuinely exists after validation means cp reintroduced it.
    let _ = await fs.rm(targetPath, ~options={recursive: true})
    MarkerPresent
  }
}

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
    let sourceValidation = await validateSourceForInstall(~source=sourceAbs, ~fs=deps.fs, ~path=deps.path)
    let targetExists = await deps.fs.fileExists(targetPath)

    switch sourceValidation {
    | Error(message) => Error(message)
    | Ok(()) =>
      if targetExists && !force {
        let shouldOverwrite = await confirmOverwrite(targetPath)
        if !shouldOverwrite {
          Error("Copy cancelled by user")
        } else {
          let _ = await deps.fs.rm(targetPath, ~options={recursive: true})
          let _ = await deps.fs.mkdir(registryRoot, ~options={recursive: true})
          let _ = await deps.fs.cp(sourceAbs, targetPath, ~options={recursive: true})
          let markerPath = deps.path.join(targetPath, ".blueprint-provenance")
          let forgedMarker = "Refusing to install " ++ sourceAbs ++ ": source already contains a .blueprint-provenance marker"
          switch await removeCopiedMarkerIfPresent(~fs=deps.fs, ~targetPath, ~markerPath) {
          | MarkerInspectFailed(reason) => Error("Failed to install " ++ name ++ ": " ++ reason)
          | MarkerPresent => Error(forgedMarker)
          | MarkerAbsent =>
            let _ = await deps.fs.writeFile(
              markerPath,
              "source: " ++ sourceAbs ++ "\ninstalled_at: " ++ Date.toISOString(Date.make()) ++ "\n",
              ~options={encoding: "utf8"},
            )

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
        }
      } else {
        if targetExists {
          let _ = await deps.fs.rm(targetPath, ~options={recursive: true})
        }
        let _ = await deps.fs.mkdir(registryRoot, ~options={recursive: true})
        let _ = await deps.fs.cp(sourceAbs, targetPath, ~options={recursive: true})
        let markerPath = deps.path.join(targetPath, ".blueprint-provenance")
        let forgedMarker = "Refusing to install " ++ sourceAbs ++ ": source already contains a .blueprint-provenance marker"
        switch await removeCopiedMarkerIfPresent(~fs=deps.fs, ~targetPath, ~markerPath) {
        | MarkerInspectFailed(reason) => Error("Failed to install " ++ name ++ ": " ++ reason)
        | MarkerPresent => Error(forgedMarker)
        | MarkerAbsent =>
          let _ = await deps.fs.writeFile(
            markerPath,
            "source: " ++ sourceAbs ++ "\ninstalled_at: " ++ Date.toISOString(Date.make()) ++ "\n",
            ~options={encoding: "utf8"},
          )

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
