let buildGenerateSearchPaths = Utils.buildGenerateSearchPaths

let copyTemplateToRegistry = TemplateRegistry.copyTemplateToRegistry

let removeTemplateFromRegistry = TemplateRegistry.removeTemplateFromRegistry

let main: unit => promise<unit> = async () => {
  let deps: Ports.deps = if Runtime.isDeno() {
    {
      fs: DenoFileSystem.make(),
      path: DenoPath.make(),
      process: DenoProcess.make(),
      shell: DenoShell.make(),
      interactiveIO: DenoInteractiveIO.make(()),
      argParser: DenoArgParser.make(),
      yamlParser: DenoYamlParser.make(),
      ejs: DenoEjs.make(),
    }
  } else {
    {
      fs: NodeJsFileSystem.make(),
      path: NodeJsPath.make(),
      process: NodeJsProcess.make(),
      shell: NodeJsShell.make(),
      interactiveIO: NodeJsInteractiveIO.make(()),
      argParser: NodeJsArgParser.make(),
      yamlParser: NodeJsYamlParser.make(),
      ejs: NodeJsEjs.make(),
    }
  }

  let argv = deps.process.argv()
  let args = Array.slice(argv, ~start=2)
  await Router.route(~deps, ~args)
}
