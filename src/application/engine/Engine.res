// Engine — 3-phase pipeline orchestrator

open Discovery

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
  shellErrors?: array<string>,
}

let runPostHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~result: generateResult,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
) => promise<result<generateResult, string>> = async (~config, ~projectRoot, ~result, ~shell, ~process, ~path) => {
  switch config {
  | None => Ok(result)
  | Some(c) => {
      let shellConfig = c.shell
      let hookResult = await Hooks.run(~config=c, ~projectRoot, ~hookType=Hooks.PostGenerate, ~shellConfig, ~shell, ~process, ~path)
      switch hookResult {
      | Error(e) => Error(e)
      | Ok() => Ok(result)
      }
    }
  }
}

let runPhase0: (
  ~io: Ports.interactiveIO,
  ~generator: generator,
  ~context: 'context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<(Phase0.phase0Result, array<ConflictResolver.conflictDecision>), string>> = async (~io, ~generator, ~context, ~outputDir, ~force, ~fs, ~path) => {
  let phase0Result = await Phase0.run(~io, ~generator, ~context, ~outputDir, ~force, ~fs, ~path)

  switch phase0Result {
  | Error(e) => {
      io.close()
      Error(e)
    }
  | Ok(p0) => {
      let conflictResult = await ConflictResolver.resolveConflicts(
        ~io,
        ~conflicts=p0.conflicts->Array.map(c => {
          {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath}
        }),
        ~force,
      )

      switch conflictResult {
      | Error(e) => {
          io.close()
          Error(e)
        }
      | Ok(decisions) => Ok((p0, decisions))
      }
    }
  }
}

let runPhase1: (
  ~io: Ports.interactiveIO,
  ~templates: array<Template.template>,
  ~mergedContext: Context.context,
  ~outputDir: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
) => promise<result<Phase1.phase1Result, string>> = async (~io, ~templates, ~mergedContext, ~outputDir, ~shellConfig, ~fs, ~path, ~process) => {
  let phase1Result = await Phase1.run(
    ~templates,
    ~context=mergedContext,
    ~outputDir,
    ~conflictDecisions=None,
    ~shellConfig,
    ~fs,
    ~path,
    ~process,
  )

  switch phase1Result {
  | Error(e) => {
      io.close()
      Error(e.message)
    }
  | Ok(p1) => Ok(p1)
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

  let cwd = switch await fs.fileExists(generator.path) {
  | true => generator.path
  | false => "."
  }

  let context = Context.build(
    ~cwd,
    ~actionfolder=generator.path,
    ~name,
    ~cliAttributes,
    (),
  )

  let preHookResult: result<unit, string> = switch config {
          | None => Ok()
          | Some(c) => {
              let shellConfig = c.shell
              await Hooks.run(~config=c, ~projectRoot=cwd, ~hookType=Hooks.PreGenerate, ~shellConfig, ~shell, ~process=proc, ~path)
            }
          }

  switch preHookResult {
  | Error(e) => {
      io.close()
      Error(e)
    }
  | Ok() => {
      let phase0Outcome = await runPhase0(
        ~io,
        ~generator,
        ~context,
        ~outputDir,
        ~force,
        ~fs,
        ~path,
      )

      switch phase0Outcome {
      | Error(e) => Error(e)
      | Ok((p0, _decisions)) => {
          io.close()

          // Wrap prompt answers into attrValue (PromptResolver returns dict<string>)
          let wrappedAnswers = Dict.make()
          p0.resolvedAttributes->Dict.toArray->Array.forEach(((k, v)) => {
            Dict.set(wrappedAnswers, k, Context.Scalar(v))
          })

          let mergedContext = Context.build(
            ~cwd=context.cwd,
            ~actionfolder=context.actionfolder,
            ~name,
            ~cliAttributes,
            ~promptAnswers=wrappedAnswers,
            (),
          )

          let shellConfig = switch config {
          | Some(c) => c.shell
          | None => None
          }

          let phase1Outcome = await runPhase1(
            ~io,
            ~templates=generator.templates,
            ~mergedContext,
            ~outputDir,
            ~shellConfig,
            ~fs,
            ~path,
            ~process=proc,
          )

          switch phase1Outcome {
          | Error(e) => Error(e)
          | Ok(p1) => {
              let phase2Result = await Phase2.run(
                ~stagingDir=p1.stagingDir,
                ~outputDir,
                ~renderedFiles=p1.renderedFiles,
                ~shellCommands=p1.shellCommands,
                ~shellConfig=shellConfig,
                ~fs,
                ~path,
                ~process=proc,
                ~shell,
              )

              switch phase2Result {
              | Error(e) => {
                  io.close()
                  Error(e.message)
                }
              | Ok(p2) => {
                  let shellErrs: option<array<string>> = p2.shellErrors
                  let result: generateResult = {
                    filesCreated: p2.filesCreated,
                    filesInjected: p2.filesInjected,
                    commandsExecuted: p2.commandsExecuted,
                    classification: generator.name,
                    shellErrors: ?shellErrs,
                  }
                  let finalResult = await runPostHook(~config, ~projectRoot=cwd, ~result, ~shell, ~process=proc, ~path)
                  io.close()
                  finalResult
                }
              }
            }
          }
        }
      }
    }
  }
}

let runWithConfig: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~force: bool,
  ~deps: Ports.deps,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~force,
  ~deps,
) => {
  await run(~generator, ~name, ~cliAttributes, ~outputDir=Config.defaultOutputDir, ~force, ~deps)
}