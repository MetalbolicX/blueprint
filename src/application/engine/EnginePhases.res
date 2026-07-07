// EnginePhases.res
open Discovery

let runPhase0: (
  ~io: Ports.interactiveIO,
  ~generator: generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<(Phase0.phase0Result, array<ConflictResolver.conflictDecision>), string>> = async (~io, ~generator, ~context, ~outputDir, ~force, ~fs, ~path) => {
  let phase0Result = await Phase0.run(~io, ~generator, ~context, ~outputDir, ~force, ~fs, ~path)

  switch phase0Result {
  | Error(e) =>
    io.close()
    Error(e)
  | Ok(p0) =>
    let conflictResult = await ConflictResolver.resolveConflicts(
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
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
) => promise<result<Phase1.phase1Result, string>> = async (~io, ~templates, ~mergedContext, ~outputDir, ~conflictDecisions, ~shellConfig, ~fs, ~path, ~process) => {
  let phase1Result = await Phase1.run(
    ~templates,
    ~context=mergedContext,
    ~outputDir,
    ~conflictDecisions,
    ~shellConfig,
    ~fs,
    ~path,
    ~process,
  )

  switch phase1Result {
  | Error(e) =>
    io.close()
    Error(e.message)
  | Ok(p1) => Ok(p1)
  }
}
