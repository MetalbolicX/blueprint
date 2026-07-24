// ListCmd — list generators command
module H = Helpers

let runList: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
  switch H.requireGeneratorName(~deps, ~name) {
  | None => ()
  | Some(generatorName) => {
      switch await H.resolveGeneratorDir(~deps, ~name=generatorName) {
      | None => {
          Console.error("Error: generator not found: " ++ generatorName)
          deps.process.exit(1)
        }
      | Some(generatorDir) => {
          let manifestPath = deps.path.join(generatorDir, "manifest.yaml")
          let manifestResult = if await deps.fs.fileExists(manifestPath) {
            let manifestContent = await deps.fs.readFile(manifestPath, ~options={encoding: "utf8"})
            Manifest.parse(manifestContent)
          } else {
            Error("manifest missing")
          }

          let entries = try {
            await deps.fs.readdir(generatorDir, ~options={withFileTypes: false})
          } catch {
          | _ => []
          }
          let actionDirs =
            await Promise.all(entries->Array.map(async entry => {
              let maybeDir = deps.path.join(generatorDir, entry)
              let stat = try {
                Some(await deps.fs.stat(maybeDir))
              } catch {
              | _ => None
              }
              switch stat {
              | Some(s) if s.isDirectory() => Some(maybeDir)
              | _ => None
              }
            }))
          let templates =
            await Promise.all(actionDirs->Array.filterMap(x => x)->Array.map(async actionDir => {
              let files = try {
                await deps.fs.readdir(actionDir, ~options={withFileTypes: false})
              } catch {
              | _ => []
              }
              files
              ->Array.filter(Template.isTemplateFile)
              ->Array.map(filename => deps.path.join(actionDir, filename))
            }))

          let templatePaths = templates->Array.reduce([], (acc, current) => acc->Array.concat(current))

          Console.log("Generator: " ++ generatorName)
          Console.log("Path: " ++ generatorDir)

          Console.log("Prompts:")
          switch manifestResult {
          | Ok(manifest) =>
            switch manifest.prompts {
            | Some(prompts) if Array.length(prompts) > 0 =>
              prompts->Array.forEach(prompt => {
                let promptType = Manifest.promptTypeToString(prompt.promptType)
                Console.log("  - " ++ prompt.name ++ " (" ++ promptType ++ ")")
              })
            | _ => Console.log("  (none)")
            }
          | Error(_) => Console.log("  (manifest missing or invalid)")
          }

          Console.log("Templates:")
          if Array.length(templatePaths) == 0 {
            Console.log("  (none)")
          } else {
            templatePaths->Array.forEach(templatePath => Console.log("  - " ++ templatePath))
          }
        }
      }
    }
  }
}
