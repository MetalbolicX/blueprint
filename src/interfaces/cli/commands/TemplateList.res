// TemplateList — list installed templates from the global registry
let runTemplateList: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<unit> = async (~deps, ~fs, ~path) => {
  let homeDir = deps.process.homedir()
  let globalConfig = await Config.loadMergedGlobalConfig(~fs, ~path, ~homeDir)

  if Array.length(globalConfig.registry) == 0 {
    Console.log("No templates installed in registry.")
  } else {
    globalConfig.registry
    ->Array.forEach(entry => Console.log(entry.name ++ "\t" ++ entry.source ++ "\t" ++ entry.path))
  }
}
