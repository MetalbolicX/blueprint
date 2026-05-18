// Engine — 3-phase pipeline orchestrator

open Discovery

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
}

let runPostHook: (
  ~config: option<Config.config>,
  ~cwd: string,
  ~result: generateResult,
) => promise<result<generateResult, string>> = async (~config, ~cwd, ~result) => {
  switch config {
  | None => Ok(result)
  | Some(c) => {
      let hookResult = await Hooks.run(~config=c, ~cwd, ~hookType=Hooks.PostGenerate)
      switch hookResult {
      | Error(e) => Error(e)
      | Ok() => Ok(result)
      }
    }
  }
}

let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
  ~config=?,
) => {
  let rl = Bindings.Readline.createInterface(
    ~input=Bindings.Readline.stdin,
    ~output=Bindings.Readline.stdout,
    (),
  )

  let cwd = switch await Bindings.Fs.fileExists(generator.path) {
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
  | Some(c) => await Hooks.run(~config=c, ~cwd=outputDir, ~hookType=Hooks.PreGenerate)
  }

  switch preHookResult {
  | Error(e) => {
      rl.close()
      Error(e)
    }
  | Ok() => {

      let phase0Result = await Phase0.run(
    ~rl,
    ~generator,
    ~context,
    ~outputDir,
    ~force,
  )

      switch phase0Result {
      | Error(e) => {
          rl.close()
          Error(e)
        }
      | Ok(p0) => {
      let conflictResult = await ConflictResolver.resolveConflicts(
        ~rl,
        ~conflicts=p0.conflicts->Array.map(c => {
          {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath}
        }),
        ~force,
      )

      switch conflictResult {
      | Error(e) => {
          rl.close()
          Error(e)
        }
      | Ok(decisions) => {
          rl.close()

          let mergedContext = Context.build(
            ~cwd=context.cwd,
            ~actionfolder=context.actionfolder,
            ~name,
            ~cliAttributes,
            ~promptAnswers=p0.resolvedAttributes,
            (),
          )

          let phase1Result = await Phase1.run(
            ~templates=generator.templates,
            ~context=mergedContext,
            ~outputDir,
            ~conflictDecisions=Some(decisions),
          )

          switch phase1Result {
          | Error(e) => {
              rl.close()
              Error(e.message)
            }
          | Ok(p1) => {
              let phase2Result = await Phase2.run(
                ~stagingDir=p1.stagingDir,
                ~outputDir,
                ~renderedFiles=p1.renderedFiles,
                ~shellCommands=p1.shellCommands,
              )

              switch phase2Result {
              | Error(e) => {
                  rl.close()
                  Error(e.message)
                }
              | Ok(p2) => {
                  let result = {
                    filesCreated: p2.filesCreated,
                    filesInjected: p2.filesInjected,
                    commandsExecuted: p2.commandsExecuted,
                    classification: generator.name,
                  }
                  let finalResult = await runPostHook(~config, ~cwd=outputDir, ~result)
                  rl.close()
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
  }
}

let runWithConfig: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~force,
) => {
  await run(~generator, ~name, ~cliAttributes, ~outputDir=Config.defaultOutputDir, ~force)
}
