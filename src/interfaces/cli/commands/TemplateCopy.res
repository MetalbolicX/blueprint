// TemplateCopy — copy a template into the global registry
let runTemplateCopy: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~force: bool,
) => promise<unit> = async (~deps, ~fs, ~path, ~name, ~force) => {
  switch await ConfigContext.loadConfigContext(~deps, ~fs, ~path) {
  | Error(e) => {
      Console.error("Error: " ++ e)
      deps.process.exit(1)
    }
  | Ok(ctx) => {
  let projectPaths = ["_templates", "templates", "generators"]
  let sourceSearchPaths = projectPaths->Array.concat(ctx.merged.templates)
  let generators = await Discovery.discover(~fs, ~path, ~yamlParser=deps.yamlParser, ~searchPaths=sourceSearchPaths, ())

  switch Discovery.findByClassification(generators, name) {
  | None => {
      Console.error("Error: template not found: " ++ name)
      deps.process.exit(1)
    }
    | Some(generator) => {
      let registryRoot = Utils.globalTemplateRegistryRoot(~deps)
      let configPath = Utils.globalConfigPath(~deps)
      let confirmed = await deps.interactiveIO.askConfirm(
        ~question="Install template " ++ name ++ " from " ++ generator.path ++ " into the global registry?",
        ~defaultYes=false,
      )
      if !confirmed {
        Console.log("Template installation cancelled")
      } else {
      let result = await TemplateRegistry.copyTemplateToRegistry(
        ~deps,
        ~fs,
        ~path,
        ~name,
        ~sourcePath=generator.path,
        ~registryRoot,
        ~configPath,
        ~globalConfig=ctx.globalConfig,
        ~force,
        ~confirmOverwrite=targetPath =>
          deps.interactiveIO.askConfirm(
            ~question="Template already exists at " ++ targetPath ++ ". Overwrite?",
            ~defaultYes=false,
          ),
      )
      switch result {
      | Ok(_) =>
        Console.log("Installed template: " ++ name ++ " -> " ++ deps.path.join(registryRoot, name))
      | Error(e) => {
          Console.error("Error: " ++ e)
          deps.process.exit(1)
      }
      }
      }
    }
  }
  }
  }
}
