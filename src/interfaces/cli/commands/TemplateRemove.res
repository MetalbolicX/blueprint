// TemplateRemove — remove a template from the global registry
let runTemplateRemove: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
) => promise<unit> = async (~deps, ~fs, ~path, ~name) => {
  let homeDir = deps.process.homedir()
  let globalConfig = await Config.loadMergedGlobalConfig(~fs, ~path, ~homeDir)
  let configPath = Utils.globalConfigPath(~deps)
  let result = await TemplateRegistry.removeTemplateFromRegistry(
    ~deps,
    ~fs,
    ~path,
    ~name,
    ~configPath,
    ~globalConfig,
  )
  switch result {
  | Ok(_) => Console.log("Removed template: " ++ name)
  | Error(e) => {
      Console.error("Error: " ++ e)
      deps.process.exit(1)
    }
  }
}
