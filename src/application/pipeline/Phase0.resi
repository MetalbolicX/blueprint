type conflictFile = {
  sourcePath: string,
  targetPath: string,
}

type phase0Result = {
  resolvedAttributes: dict<string>,
  conflicts: array<conflictFile>,
  resolvedTargets: array<TemplateRenderer.resolvedTarget>,
}

let detectRenderedConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
  ~ejs: Ports.ejs,
  ~attributes: dict<string>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<array<conflictFile>, string>>

let run: (
  ~io: Ports.interactiveIO,
  ~ejs: Ports.ejs,
  ~generator: Discovery.generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<phase0Result, string>>