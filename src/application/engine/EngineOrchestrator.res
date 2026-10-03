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
  ~projectRoot: string=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, Commit.phase2Error>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
  ~config=?,
  ~projectRoot=?,
  ~deps,
) => {
  let {fs, path, process: proc, shell, interactiveIO: io, ejs, yamlParser, fetcher, pathSecurity, shellBuilder, envFilter} = deps
  let resolvedProjectRoot = projectRoot->Option.getOr(proc.cwd())

  // Derive the shared OS temp root through the filesystem port, whose Node adapter
  // creates staging directories under os.tmpdir().
  let tmpRootProbe = await fs.makeStagingDir("blueprint-tmp-root-probe")
  let tmpRoot = path.dirname(tmpRootProbe)
  await EngineLifecycle.cleanupPath(~target=tmpRootProbe, ~fs)

  let isDryRun = config->Option.flatMap(c => c.dryRun)->Option.getOr(false)

  // Phase 0: setup (unconditional)
  fetcher.clearCache()
  if !isDryRun {
    await EngineLifecycle.cleanupOrphans(~outputDir, ~fs, ~path, ~tmpRoot)
  }

  let context = await EngineContext.buildInitialContext(
    ~fs,
    ~generatorPath=generator.path,
    ~name,
    ~cliAttributes,
  )

  // Pre-hook — resolve generator vs project hook precedence; generator wins
  // Generator hook: scriptRoot=generator.path, cwd=outputDir
  // Project hook: scriptRoot=projectRoot, cwd=outputDir
  let (preHookCmd, preScriptRoot, preCwd) = switch generator.manifest {
  | Some(m) =>
    switch m.hooks {
    | Some(gh) =>
      switch gh.preGenerate {
      | Some(s) =>
        // Generator declares pre-hook: use it, log if project hook is shadowed
        switch config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.preGenerate) {
        | Some(_) => Console.info("Generator pre-hook shadows project .blueprint.yaml pre_generate hook")
        | None => ()
        }
        let hookCmd: Config.hookCommand = {command: s}
        (Some(hookCmd), generator.path, outputDir)
      | None =>
        let projectHook = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.preGenerate)
        (projectHook, resolvedProjectRoot, outputDir)
      }
    | None =>
      let projectHook = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.preGenerate)
      (projectHook, resolvedProjectRoot, outputDir)
    }
  | None =>
    let projectHook = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.preGenerate)
    (projectHook, resolvedProjectRoot, outputDir)
  }

  let preHookResult = switch await EngineHooks.runPreHook(
    ~config,
    ~projectRoot=resolvedProjectRoot,
    ~hooks=deps.hooks,
    ~shell,
    ~process=proc,
    ~path,
    ~fs,
    ~scriptRoot=preScriptRoot,
    ~cwd=preCwd,
    ~preHook=preHookCmd,
  ) {
  | Error(e) =>
    io.close()
    Error({Commit.message: e})
  | Ok(hookRes) => Ok(hookRes)
  }

  // Parse hook stdout into attributes (fail-closed on malformed output)
  let hookAttributes: result<option<dict<Context.attrValue>>, Commit.phase2Error> = switch preHookResult {
  | Error(_) => Ok(None)
  | Ok(hookRes) =>
    switch HookContext.parse(~stdout=hookRes.output, ~yamlParser) {
    | Ok(attrs) => Ok(Some(attrs))
    | Error(e) => io.close(); Error({Commit.message: e})
    }
  }

  // For bindPhase, we pass io if preHook succeeded (errors already handled above)
  let preResult: result<Ports.interactiveIO, Commit.phase2Error> = switch preHookResult {
  | Error(e) => Error(e) // already closed above
  | Ok(_) => Ok(io)
  }

  // Phase 0: prompt resolution + conflict detection
  let phase0Result = await bindPhase(
    ~prev=preResult,
    ~next=(async (io) => {
      // NOTE: io.close() is called inside EnginePhases.runPhase0 on error
      switch await EnginePhases.runPhase0(
        ~io,
        ~ejs,
        ~generator,
        ~context,
        ~outputDir,
        ~force,
        ~fs,
        ~path,
        ~pathSecurity,
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
      // Extract hookAttributes from the result (errors already handled above)
      let hookAttrs = switch hookAttributes {
      | Error(_) => None
      | Ok(attrs) => attrs
      }
      let mergedContext = EngineContext.buildMergedContext(
        ~initialContext=context,
        ~name,
        ~cliAttributes,
        ~promptAnswers=p0.resolvedAttributes,
        ~hookAttributes=?hookAttrs,
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
        ~pathSecurity,
        ~ejs,
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
      let commitRollbackRef: ref<option<unit => promise<unit>>> = ref(None)
      EngineLifecycle.registerSignalHandlers(~process=proc, ~stagingDirRef, ~commitRollbackRef, ~fs)
      if isDryRun {
        stagingDirRef.contents = None
        proc.removeSignalListeners()
        Console.log(
          "Dry run — would generate " ++ Int.toString(p1.renderedFiles->Array.length) ++ " file(s)",
        )
        switch await Commit.rollback(p1.stagingDir, ~tmpRoot, ~path, ~fs, ~pathSecurity) {
        | Ok() => ()
        | Error(message) => Console.warn("Warning: could not clean staging directory " ++ p1.stagingDir ++ ": " ++ message)
        }
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
          ~fetcher,
          ~pathSecurity,
          ~shellBuilder,
          ~envFilter,
          ~tmpRoot,
          ~commitRollbackRef,
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
            }
            // Post-hook: same precedence logic as pre-hook
            let (postHookCmd, postScriptRoot, postCwd) = switch generator.manifest {
            | Some(m) =>
              switch m.hooks {
              | Some(gh) =>
              switch gh.postGenerate {
              | Some(s) =>
                switch config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.postGenerate) {
                | Some(_) => Console.info("Generator post-hook shadows project .blueprint.yaml post_generate hook")
                | None => ()
                }
                let hookCmd: Config.hookCommand = {command: s}
                (Some(hookCmd), generator.path, outputDir)
              | None =>
                  let projectHook = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.postGenerate)
                  (projectHook, resolvedProjectRoot, outputDir)
                }
              | None =>
                let projectHook = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.postGenerate)
                (projectHook, resolvedProjectRoot, outputDir)
              }
            | None =>
              let projectHook = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.postGenerate)
              (projectHook, resolvedProjectRoot, outputDir)
            }
            let finalResult = await EngineHooks.runPostHook(
              ~config,
              ~projectRoot=resolvedProjectRoot,
              ~result,
              ~hooks=deps.hooks,
              ~shell,
              ~process=proc,
              ~path,
              ~fs,
              ~scriptRoot=postScriptRoot,
              ~cwd=postCwd,
              ~postHook=postHookCmd,
            )
            io.close()
            switch finalResult {
            | Ok(r) => Ok(r)
            | Error(e) => Error({Commit.message: e ++ "; files were already committed; output tree is partially updated"})
            }
          }
        }
      }
    }),
  )
}
