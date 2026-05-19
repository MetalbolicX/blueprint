type conflictFile = {
  sourcePath: string,
  targetPath: string,
}

type phase0Result = {
  resolvedAttributes: dict<string>,
  conflicts: array<conflictFile>,
}

let detectConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
) => promise<array<conflictFile>>

let run: (
  ~rl: Bindings.Readline.readlineInterface,
  ~generator: Discovery.generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
) => promise<result<phase0Result, string>>
