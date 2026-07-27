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
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<array<conflictFile>>

let run: (
  ~io: Ports.interactiveIO,
  ~ejs: Ports.ejs,
  ~generator: Discovery.generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<phase0Result, string>>