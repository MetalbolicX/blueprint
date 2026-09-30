let buildGenerateSearchPaths = Utils.buildGenerateSearchPaths

let copyTemplateToRegistry = TemplateRegistry.copyTemplateToRegistry

let removeTemplateFromRegistry = TemplateRegistry.removeTemplateFromRegistry

let main: unit => promise<unit> = async () => {
  let deps: Ports.deps = {
    fs: NodeJsFileSystem.make(),
    path: NodeJsPath.make(),
    process: NodeJsProcess.make(),
    shell: NodeJsShell.make(),
    interactiveIO: NodeJsInteractiveIO.make(()),
    argParser: NodeJsArgParser.make(),
    yamlParser: NodeJsYamlParser.make(),
    ejs: NodeJsEjs.make(),
  }

  let argv = deps.process.argv()
  let args = Array.slice(argv, ~start=2)
  try {
    await Router.route(~deps, ~args)
    deps.interactiveIO.close()
    deps.process.exit(0)
  } catch {
  | JsExn(error) => {
      deps.interactiveIO.close()
      let message = JsExn.message(error)->Option.getOr("interactive command failed")
      Console.error(
        "Error: " ++ message ++ ". Provide the required input on stdin; use --force for conflict prompts or configure prompts non-interactively where supported.",
      )
      deps.process.exit(1)
    }
  | _ => {
      deps.interactiveIO.close()
      Console.error("Error: interactive command failed")
      deps.process.exit(1)
    }
  }
}
