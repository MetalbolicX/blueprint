// EnginePhases.res
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
) => promise<result<(Phase0.phase0Result, array<ConflictResolver.conflictDecision>), string>> = async (~io, ~ejs, ~generator, ~context, ~outputDir, ~force, ~fs, ~path, ~pathSecurity) => {
  let phase0Result = await Phase0.run(~io, ~ejs, ~generator, ~context, ~outputDir, ~force, ~fs, ~path, ~pathSecurity)

  switch phase0Result {
  | Error(e) =>
    io.close()
    Error(e)
  | Ok(p0) =>
    let conflictResult = await ConflictRunner.resolveConflicts(
      ~io,
      ~conflicts=p0.conflicts->Array.map(c => {
        {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath}
      }),
      ~force,
    )

    switch conflictResult {
    | Error(e) =>
      io.close()
      Error(e)
    | Ok(decisions) => Ok((p0, decisions))
    }
  }
}

let runPhase1: (
  ~io: Ports.interactiveIO,
  ~templates: array<Template.template>,
  ~mergedContext: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~preResolvedTargets: array<TemplateRenderer.resolvedTarget> =?,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<Phase1.phase1Result, string>> = async (~io, ~templates, ~mergedContext, ~outputDir, ~conflictDecisions, ~preResolvedTargets=[], ~shellConfig, ~fs, ~path, ~pathSecurity, ~ejs, ~process) => {
  let phase1Result = await Phase1.run(
    ~templates,
    ~context=mergedContext,
    ~outputDir,
    ~conflictDecisions,
    ~preResolvedTargets,
    ~shellConfig,
    ~fs,
    ~path,
    ~pathSecurity,
    ~ejs,
    ~process,
  )

  switch phase1Result {
  | Error(e) =>
    io.close()
    Error(e.message)
  | Ok(p1) => Ok(p1)
  }
}
