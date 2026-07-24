// AddFile — interactive file creation command
module H = Helpers
module W = Wizard

let runAddFile: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
  switch H.requireGeneratorName(~deps, ~name) {
  | None => ()
  | Some(generatorName) => {
      switch await H.resolveGeneratorDir(~deps, ~name=generatorName) {
      | None => {
          Console.error("Error: generator not found: " ++ generatorName)
          deps.process.exit(1)
        }
      | Some(generatorDir) => {
          let actionFolderRaw = await deps.interactiveIO.ask("Action folder (default: new): ")
          let actionFolder = switch H.maybeString(actionFolderRaw) {
          | Some(v) => v
          | None => "new"
          }

          let filenameRaw = await deps.interactiveIO.ask("Template file name (e.g. index.ejs.t): ")
          let filename = H.normalizeTemplateFilename(filenameRaw->String.trim)
          let toPath = (await deps.interactiveIO.ask("to path (required): "))->String.trim

          if filename == ".ejs.t" || toPath == "" {
            Console.error("Error: template file name and 'to' are required")
            deps.process.exit(1)
          } else {
            let directives = await W.promptForDirectives(~io=deps.interactiveIO, ~toPath)
            let templateContent = W.buildFrontmatter(directives)

            let actionDir = deps.path.join(generatorDir, actionFolder)
            let targetPath = deps.path.join(actionDir, filename)
            let _ = await deps.fs.mkdir(actionDir, ~options={recursive: true})
            await deps.fs.writeFile(targetPath, templateContent)
            Console.log("Created template: " ++ targetPath)
          }
        }
      }
    }
  }
}
