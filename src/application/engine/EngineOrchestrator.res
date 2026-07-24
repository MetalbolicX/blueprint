// EngineOrchestrator.res
open Discovery
open EngineResult

let bindPhase = async (
  ~prev: result<'a, Commit.phase2Error>,
  ~next: 'a => promise<result<'b, Commit.phase2Error>>,
) => {
  switch prev {
  | Error(e) => Error(e)
  | Ok(v) => await next(v)
  }
}

let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, Commit.phase2Error>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
  ~config=?,
  ~deps,
) => {
  let {fs, path, process: proc, shell, interactiveIO: io} = deps

  // Phase 0: setup (unconditional)
  Fetcher.clearCache()
  await EngineLifecycle.cleanupOrphans(~outputDir, ~fs, ~path)

  let context = await EngineContext.buildInitialContext(
    ~fs,
    ~generatorPath=generator.path,
    ~name,
    ~cliAttributes,
  )

  // Pre-hook
  let preResult = switch await EngineHooks.runPreHook(
    ~config,
    ~projectRoot=context.cwd,
    ~shell,
    ~process=proc,
    ~path,
    ~fs,
  ) {
  | Error(e) =>
    io.close()
    Error({Commit.message: e})
  | Ok() => Ok(io)
  }

  // Phase 0: prompt resolution + conflict detection
  let phase0Result = await bindPhase(
    ~prev=preResult,
    ~next=(async (io) => {
      // NOTE: io.close() is called inside EnginePhases.runPhase0 on error
      switch await EnginePhases.runPhase0(
        ~io,
        ~generator,
        ~context,
        ~outputDir,
        ~force,
        ~fs,
        ~path,
      ) {
      | Error(e) => Error({Commit.message: e})
      | Ok((p0, decisions)) => {
          io.close()
          Ok((p0, decisions))
        }
      }
    }),
  )

  // Phase 1: build merged context + render to staging
  let phase1Result = await bindPhase(
    ~prev=phase0Result,
    ~next=(async ((p0, decisions)) => {
      let mergedContext = EngineContext.buildMergedContext(
        ~initialContext=context,
        ~name,
        ~cliAttributes,
        ~promptAnswers=p0.resolvedAttributes,
      )

      let shellConfig = config->Option.flatMap(c => c.shell)

      // NOTE: io.close() is called inside EnginePhases.runPhase1 on error
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
      | Error(e) => Error({Commit.message: e})
      | Ok(p1) => Ok((p1, shellConfig))
      }
    }),
  )

  // Phase 2: dry-run or commit to output + post-hook
  await bindPhase(
    ~prev=phase1Result,
    ~next=(async ((p1, shellConfig)) => {
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
        Ok({
          filesCreated: p1.renderedFiles->Array.length,
          filesInjected: 0,
          commandsExecuted: 0,
          classification: generator.name,
        })
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
        | Error(e) => {
            io.close()
            Error(e)
          }
        | Ok(p2) => {
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
            switch finalResult {
            | Ok(r) => Ok(r)
            | Error(e) => Error({Commit.message: e})
            }
          }
        }
      }
    }),
  )
}
