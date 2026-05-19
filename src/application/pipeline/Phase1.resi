type phase1Result = {
  stagingDir: string,
  renderedFiles: array<(string, string)>,
  shellCommands: array<Template.shellCommand>,
}

type phase1Error = {
  stagingDir: string,
  message: string,
}

let resolveTargetPath: (Template.directive, Context.context) => option<string>

let run: (
  ~templates: array<Template.template>,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~shellConfig: option<Config.shellConfig>,
) => promise<result<phase1Result, phase1Error>>
