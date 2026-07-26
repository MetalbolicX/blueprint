type phase1Result = {
  stagingDir: string,
  renderedFiles: array<(string, string)>,
  shellCommands: array<Template.shellCommand>,
}

type phase1Error = {
  stagingDir: string,
  message: string,
}

let resolveTargetPath: (~ejs: Ports.ejs, Template.directive, Context.context) => result<string, string>

let run: (
  ~templates: array<Template.template>,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<phase1Result, phase1Error>>