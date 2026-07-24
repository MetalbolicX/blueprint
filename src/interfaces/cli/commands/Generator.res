// Generator — directory module aggregating all generator command sub-modules
module Helpers = Helpers
module ListCmd = ListCmd
module AddPrompt = AddPrompt
module AddFile = AddFile
module Wizard = Wizard

// Re-exports for backward-compatibility (tests access CommandsGenerator.* directly)
let normalizeTemplateFilename = Helpers.normalizeTemplateFilename
let resolveGeneratorDir = Helpers.resolveGeneratorDir
let maybeString = Helpers.maybeString
let parsePromptOptions = Helpers.parsePromptOptions
let parsePromptValidation = Helpers.parsePromptValidation

let runList = ListCmd.runList

let runAddPrompt = AddPrompt.runAddPrompt

let buildFrontmatter = Wizard.buildFrontmatter
let runAddFile = AddFile.runAddFile

// Types re-exported for test compatibility
type directiveValues = Wizard.directiveValues
type directiveKind = Wizard.directiveKind
type directiveDescriptor = Wizard.directiveDescriptor
let allDirectiveDescriptors = Wizard.allDirectiveDescriptors

let run: (~deps: Ports.deps, ~args: array<string>) => promise<unit> = async (~deps, ~args) => {
  let action = switch args[0] {
  | Some(a) => a
  | None => ""
  }

  let name = switch args[1] {
  | Some(n) if !String.startsWith(n, "-") => Some(n)
  | _ => None
  }

  switch action {
  | "" => {
      Help.printHelpFor("generator")
      deps.process.exit(0)
    }
  | "list" => await ListCmd.runList(~deps, ~name)
  | "add-prompt" => await AddPrompt.runAddPrompt(~deps, ~name)
  | "add-file" => await AddFile.runAddFile(~deps, ~name)
  | _ => {
      Console.error("Error: unknown generator action \"" ++ action ++ "\"")
      Help.printHelpFor("generator")
      deps.process.exit(1)
    }
  }
}
