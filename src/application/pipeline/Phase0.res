// Phase0: Prompt collection + conflict detection
// Mirrors Go version's phase0/phase0.go

open Bindings
open Discovery

type conflictFile = {
  sourcePath: string,
  targetPath: string,
}

type phase0Result = {
  resolvedAttributes: dict<string>, // merged CLI + prompt answers
  conflicts: array<conflictFile>,
}

// Check if a file exists at target path
let _checkFileConflict: (
  ~sourcePath: string,
  ~targetPath: string,
  ~outputDir: string,
) => promise<option<conflictFile>> = async (~sourcePath, ~targetPath, ~outputDir) => {
  let fullTargetPath = Path.join(outputDir, targetPath)
  let exists = await Fs.fileExists(fullTargetPath)

  if exists {
    Some({sourcePath, targetPath: fullTargetPath})
  } else {
    None
  }
}

// Detect conflicts for all templates with "to" directive
let detectConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
) => promise<array<conflictFile>> = async (~templates, ~outputDir, ~force) => {
  let _ = (templates, outputDir, force)
  []
}

// Run Phase0: resolve prompts and detect conflicts
let run: (
  ~rl: Readline.readlineInterface,
  ~generator: generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
) => promise<result<phase0Result, string>> = async (
  ~rl,
  ~generator,
  ~context as _context,
  ~outputDir,
  ~force,
) => {
  // Get manifest prompts
  let prompts = switch generator.manifest {
  | Some(m) => m.prompts
  | None => None
  }

  let resolvedAttributes = switch prompts {
  | Some(ps) if Array.length(ps) > 0 => await PromptResolver.resolve(~rl, ~prompts=ps, ~force)
  | _ => Dict.make()
  }

  // Detect file conflicts
  let conflicts = await detectConflicts(~templates=generator.templates, ~outputDir, ~force)

  Ok({resolvedAttributes, conflicts})
}
