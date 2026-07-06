// Engine — 3-phase pipeline orchestrator

open Discovery

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
  shellErrors?: array<string>,
}

let stagingDirPrefix = "blueprint-"
let backupDirName = ".blueprint-backup"
let staleThresholdMs = 5 * 60 * 1000

let cleanupPath: (~target: string, ~fs: Ports.fileSystem) => promise<unit> = async (~target, ~fs) => {
  try {
    let _ = await fs.rm(target, ~options={recursive: true})
    ()
  } catch {
  | _ => ()
  }
}

let parseStagingDirTimestamp = (dirName: string): option<int> => {
  let parts = String.split(dirName, "-")
  switch Array.get(parts, 1) {
  | Some(rawTs) => Int.fromString(rawTs)
  | None => None
  }
}

let cleanupOrphans: (~outputDir: string, ~fs: Ports.fileSystem, ~path: Ports.path, ~tmpRoot: string=?) => promise<unit> = async (
  ~outputDir,
  ~fs,
  ~path,
  ~tmpRoot=?,
) => {
  let resolvedTmpRoot = switch tmpRoot {
  | Some(dir) => dir
  | None => {
      let probeDir = fs.makeStagingDir()
      let probeRoot = path.dirname(probeDir)
      await cleanupPath(~target=probeDir, ~fs)
      probeRoot
    }
  }

  let tmpEntries = try {
    await fs.readdir(resolvedTmpRoot)
  } catch {
  | _ => []
  }

  let nowMs = Date.now()->Float.toInt
  let cleanupOps = tmpEntries->Array.map(async entry => {
      if String.startsWith(entry, stagingDirPrefix) {
        switch parseStagingDirTimestamp(entry) {
        | Some(createdAt) if nowMs - createdAt >= staleThresholdMs => {
            let fullPath = path.join(resolvedTmpRoot, entry)
            try {
              let stat = await fs.stat(fullPath)
              if stat.isDirectory() {
                await cleanupPath(~target=fullPath, ~fs)
              }
            } catch {
            | _ => ()
            }
          }
        | _ => ()
        }
      }
    })

  let _ = await Promise.all(cleanupOps)

  let backupDir = path.join(outputDir, backupDirName)
  let backupExists = try {
    await fs.fileExists(backupDir)
  } catch {
  | _ => false
  }

  if backupExists {
    await cleanupPath(~target=backupDir, ~fs)
  }
}

let registerSignalHandlers: (~process: Ports.process, ~stagingDirRef: ref<option<string>>, ~fs: Ports.fileSystem) => unit = (
  ~process,
  ~stagingDirRef,
  ~fs,
) => {
  let handleSignal = () => {
    let cleanupPromise = switch stagingDirRef.contents {
    | Some(stagingDir) => {
        stagingDirRef.contents = None
        cleanupPath(~target=stagingDir, ~fs)
      }
    | None => Promise.resolve()
    }

    cleanupPromise
    ->Promise.then(_ => {
      process.exit(1)
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      process.exit(1)
      Promise.resolve()
    })
    ->ignore
  }

  process.onSignal("SIGINT", handleSignal)
  process.onSignal("SIGTERM", handleSignal)
}

let runPostHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~result: generateResult,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<generateResult, string>> = async (~config, ~projectRoot, ~result, ~shell, ~process, ~path, ~fs) => {
  switch config {
  | None => Ok(result)
  | Some(c) => {
      let shellConfig = c.shell
      let hookResult = await Hooks.run(~config=c, ~projectRoot, ~hookType=Hooks.PostGenerate, ~shellConfig, ~shell, ~process, ~path, ~fs)
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

  Fetcher.clearCache()
  await cleanupOrphans(~outputDir, ~fs, ~path)

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
              await Hooks.run(~config=c, ~projectRoot=cwd, ~hookType=Hooks.PreGenerate, ~shellConfig, ~shell, ~process=proc, ~path, ~fs)
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
      | Ok((p0, decisions)) => {
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
            ~conflictDecisions=Some(decisions),
            ~shellConfig,
            ~fs,
            ~path,
            ~process=proc,
          )

          switch phase1Outcome {
          | Error(e) => Error(e)
          | Ok(p1) => {
              let stagingDirRef = ref(Some(p1.stagingDir))
              registerSignalHandlers(~process=proc, ~stagingDirRef, ~fs)
              let isDryRun = config->Option.flatMap(c => c.dryRun)->Option.getOr(false)
              if isDryRun {
                stagingDirRef.contents = None
                proc.removeSignalListeners()
                Console.log("Dry run — would generate " ++ Int.toString(p1.renderedFiles->Array.length) ++ " file(s)")
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
                  ~shellConfig=shellConfig,
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
                  let finalResult = await runPostHook(~config, ~projectRoot=cwd, ~result, ~shell, ~process=proc, ~path, ~fs)
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
}
