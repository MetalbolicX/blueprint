// Engine — 3-phase pipeline orchestrator
// Coordinates Phase0 → Phase1 → Phase2 with rollback on failure
// Mirrors Go version's engine/engine.go

open Bindings
open Phases
open Discovery

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
}

// Run the full generate pipeline
let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: Js.Dict.t<string>,
  ~outputDir: string,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
) => {
  // Create readline interface for prompts
  let rl = PromptResolver.createReadline()

  // Build initial context
  let initialContext = Context.build(
    ~cwd=Node.Process.cwd(),
    ~actionfolder=generator.path,
    ~name,
    ~cliAttributes,
    (),
  )

  // Phase0: resolve prompts and detect conflicts
  let phase0Result = await Phase0.run(
    ~rl,
    ~generator,
    ~context=initialContext,
    ~outputDir,
    ~force,
  )

  switch phase0Result {
  | Error(e) => {
      PromptResolver.closeReadline(rl)
      return Promise.resolve(Error("Phase0 failed: " ++ e))
    }
  | Ok(result) => {
      // If conflicts detected and not force mode, resolve them
      let conflicts = if Js.Array.length(result.conflicts) > 0 && !force {
        let resolution = await ConflictResolver.resolveConflicts(
          ~rl,
          ~conflicts=result.conflicts,
          ~force,
        )

        switch resolution {
        | Ok(decisions) => Some(decisions)
        | Error(_) => {
            PromptResolver.closeReadline(rl)
            return Promise.resolve(Error("Aborted by user"))
          }
        }
      } else {
        None
      }

      // Merge resolved attributes into context
      let finalContext = Context.build(
        ~cwd=Node.Process.cwd(),
        ~actionfolder=generator.path,
        ~name,
        ~cliAttributes,
        ~promptAnswers=result.resolvedAttributes,
        (),
      )

      // Phase1: stage and render templates
      let phase1Result = await Phase1.run(
        ~templates=generator.templates,
        ~context=finalContext,
        ~outputDir,
        ~conflictDecisions=conflicts,
      )

      PromptResolver.closeReadline(rl)

      switch phase1Result {
      | Error(err) => {
          // Rollback staging dir on Phase1 failure
          await Phases.Phase2.rollback(err.stagingDir)
          return Promise.resolve(Error("Phase1 failed: " ++ err.message))
        }
      | Ok(phase1) => {
          // Phase2: commit staged files to output
          let phase2Result = await Phase2.run(
            ~stagingDir=phase1.stagingDir,
            ~outputDir,
            ~renderedFiles=phase1.renderedFiles,
            ~shellCommands=phase1.shellCommands,
          )

          switch phase2Result {
          | Ok(r) => Promise.resolve(Ok({
              filesCreated: r.filesCreated,
              filesInjected: r.filesInjected,
              commandsExecuted: r.commandsExecuted,
              classification: generator.name,
            }))
          | Error(err) => Promise.resolve(Error("Phase2 failed: " ++ err.message))
          }
        }
      }
    }
  }
}

// Load config and run generator
let runWithConfig: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: Js.Dict.t<string>,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~force,
) => {
  // Load .fluxo.yaml config
  let configResult = await Config.loadFrom(Node.Process.cwd())

  let config = switch configResult {
  | Ok(Some(cfg)) => cfg
  | Ok(None) => { hooks: None, output: None }
  | Error(_) => { hooks: None, output: None }
  }

  let outputDir = switch config.output {
  | Some(o) => o
  | None => Config.defaultOutputDir
  }

  // Run pre-generate hook
  let hookResult = await Hooks.run(~config, ~cwd=Node.Process.cwd())
  switch hookResult {
  | Ok(_) => ()
  | Error(e) => return Promise.resolve(Error("Pre-generate hook failed: " ++ e))
  }

  // Run pipeline
  let result = await run(
    ~generator,
    ~name,
    ~cliAttributes,
    ~outputDir,
    ~force,
  )

  // Run post-generate hook
  let _ = await Hooks.run(~config, ~cwd=Node.Process.cwd())

  Promise.resolve(result)
}