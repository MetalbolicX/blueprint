// EngineOrchestrator.res
open Discovery
open EngineResult

let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
  ~config=?,
  ~deps,
) => {
  let {fs, path, process: proc, shell, interactiveIO: io} = deps

  Fetcher.clearCache()
  await EngineLifecycle.cleanupOrphans(~outputDir, ~fs, ~path)

  let context = await EngineContext.buildInitialContext(
    ~fs,
    ~generatorPath=generator.path,
    ~name,
    ~cliAttributes,
  )

  switch await EngineHooks.runPreHook(~config, ~projectRoot=context.cwd, ~shell, ~process=proc, ~path, ~fs) {
  | Error(e) =>
    io.close()
    Error(e)
  | Ok() =>
    switch await EnginePhases.runPhase0(~io, ~generator, ~context, ~outputDir, ~force, ~fs, ~path) {
    | Error(e) => Error(e)
    | Ok((p0, decisions)) =>
      io.close()

      let mergedContext = EngineContext.buildMergedContext(
        ~initialContext=context,
        ~name,
        ~cliAttributes,
        ~promptAnswers=p0.resolvedAttributes,
      )

      let shellConfig = config->Option.flatMap(c => c.shell)

      switch await EnginePhases.runPhase1(
        ~io,
        ~templates=generator.templates,
        ~mergedContext,
        ~outputDir,
        ~conflictDecisions=Some(decisions),
        ~shellConfig,
        ~fs,
        ~path,
        ~process=proc,
      ) {
      | Error(e) => Error(e)
      | Ok(p1) =>
        let stagingDirRef = ref(Some(p1.stagingDir))
        EngineLifecycle.registerSignalHandlers(~process=proc, ~stagingDirRef, ~fs)
        let isDryRun = config->Option.flatMap(c => c.dryRun)->Option.getOr(false)

        if isDryRun {
          stagingDirRef.contents = None
          proc.removeSignalListeners()
          Console.log(
            "Dry run — would generate " ++ Int.toString(p1.renderedFiles->Array.length) ++ " file(s)",
          )
          let _ = await Commit.rollback(p1.stagingDir, ~fs)
          let result: generateResult = {
            filesCreated: p1.renderedFiles->Array.length,
            filesInjected: 0,
            commandsExecuted: 0,
            classification: generator.name,
          }
          Ok(result)
        } else {
          let phase2Result = await Phase2.run(
            ~stagingDir=p1.stagingDir,
            ~outputDir,
            ~renderedFiles=p1.renderedFiles,
            ~shellCommands=p1.shellCommands,
            ~shellConfig,
            ~fs,
            ~path,
            ~process=proc,
            ~shell,
          )

          stagingDirRef.contents = None
          proc.removeSignalListeners()

          switch phase2Result {
          | Error(e) =>
            io.close()
            Error(e.message)
          | Ok(p2) =>
            let result: generateResult = {
              filesCreated: p2.filesCreated,
              filesInjected: p2.filesInjected,
              commandsExecuted: p2.commandsExecuted,
              classification: generator.name,
              shellErrors: ?p2.shellErrors,
            }
            let finalResult = await EngineHooks.runPostHook(
              ~config,
              ~projectRoot=context.cwd,
              ~result,
              ~shell,
              ~process=proc,
              ~path,
              ~fs,
            )
            io.close()
            finalResult
          }
        }
      }
    }
  }
}
