// AddPrompt — interactive prompt addition command
open ManifestYamlEditor

module H = Helpers

let runAddPrompt: (~deps: Ports.deps, ~name: option<string>) => promise<unit> = async (~deps, ~name) => {
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
          if !(await deps.fs.fileExists(manifestPath)) {
            Console.error("Error: manifest.yaml not found at " ++ manifestPath)
            deps.process.exit(1)
          } else {
            let promptName = (await deps.interactiveIO.ask("Prompt variable name: "))->String.trim
            let description = (await deps.interactiveIO.ask("Prompt message: "))->String.trim
            let promptTypeInput = await deps.interactiveIO.ask("Prompt type [input/select/confirm/multi-select] (default: input): ")
            let promptType = Manifest.parsePromptTypeFromInput(promptTypeInput)

            let defaultValue = await deps.interactiveIO.ask("Default value (optional): ")
            let whenExpr = await deps.interactiveIO.ask("Show condition (optional EJS expression): ")

            let options = switch promptType {
            | Manifest.Select | Manifest.MultiSelect => {
                let rawOptions =
                  await deps.interactiveIO.ask(
                    "Options (comma-separated, optional label:value format): ",
                  )
                H.parsePromptOptions(rawOptions)
              }
            | _ => None
            }

            let validatePattern = await deps.interactiveIO.ask("Validation regex (optional): ")
            let validateMessage =
              if validatePattern->String.trim == "" {
                ""
              } else {
                await deps.interactiveIO.ask("Validation error message: ")
              }

            if promptName == "" || description == "" {
              Console.error("Error: prompt name and message are required")
              deps.process.exit(1)
            } else {
              let prompt: Manifest.prompt = {
                name: promptName,
                promptType,
                description,
                default: ?H.maybeString(defaultValue),
                when_: ?H.maybeString(whenExpr),
                options: ?options,
                validate: ?H.parsePromptValidation(validatePattern, validateMessage),
              }

              let manifestContent = await deps.fs.readFile(manifestPath, ~options={encoding: "utf8"})
              switch appendPromptPreservingComments(~yamlContent=manifestContent, ~prompt) {
              | Error(e) => {
                  Console.error("Error: " ++ e)
                  deps.process.exit(1)
                }
              | Ok(updated) => {
                  await deps.fs.writeFile(manifestPath, updated)
                  Console.log("Added prompt '" ++ promptName ++ "' to " ++ manifestPath)
                  deps.interactiveIO.close()
                }
              }
            }
          }
        }
      }
    }
  }
}
