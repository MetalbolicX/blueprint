// EnginePhases.resi
open Discovery

let runPhase0: (
  ~io: Ports.interactiveIO,
  ~ejs: Ports.ejs,
  ~generator: generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<(Phase0.phase0Result, array<ConflictResolver.conflictDecision>), string>>

let runPhase1: (
  ~io: Ports.interactiveIO,
  ~templates: array<Template.template>,
  ~mergedContext: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<Phase1.phase1Result, string>>
