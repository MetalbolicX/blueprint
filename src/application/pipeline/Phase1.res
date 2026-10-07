// Phase1: Staging, rendering, injection dispatch, shell queue
// Templates are rendered to a temp staging directory
// Mirrors Go version's phase1/phase1.go

open Template

type phase1Result = {
  stagingDir: string,
  renderedFiles: array<(string, string)>, // (source, target) pairs
  shellCommands: array<shellCommand>,
}

type phase1Error = {
  stagingDir: string,
  message: string,
}

// Internal: per-template slot captured by a parallel render branch.
// Branches return these instead of mutating shared arrays; the post-Promise.all
// collection pass walks results in source order so ordering is deterministic
// regardless of which branch's I/O finishes first.
type renderSlot = {
  sourcePath: string,
  targetPath: string,
  shellCmds: array<shellCommand>,
}

// Re-exported alias so tests + external callers using `Phase1.resolveTargetPath` keep compiling.
let resolveTargetPath = TemplateRenderer.resolveTargetPath

let _prepareTemplate: (
  ~template: template,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~preResolvedTargets: array<TemplateRenderer.resolvedTarget> =?,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<option<(string, string, string, array<shellCommand>)>, string>> = async (
  ~template,
  ~context,
  ~outputDir,
  ~conflictDecisions,
  ~preResolvedTargets=[],
  ~shellConfig,
  ~fs,
  ~path,
  ~pathSecurity,
  ~ejs,
  ~process,
) => {
  let renderResult = await TemplateRenderer.render(
    ~template,
    ~context,
    ~outputDir,
    ~conflictDecisions,
    ~preResolvedTargets,
    ~fs,
    ~path,
    ~pathSecurity,
    ~ejs,
    ~process,
  )
  switch renderResult {
  | Error(e) => Error(e)
  | Ok(None) => Ok(None)
  | Ok(Some({sourcePath, targetPath, renderedBody})) =>
    switch ShellQueue.collectTemplate(
      template,
      shellConfig,
      ~actionfolder=context.actionfolder,
      ~path,
      ~process,
    ) {
    | Error(e) => Error(e)
    | Ok(shellCmds) => Ok(Some((sourcePath, targetPath, renderedBody, shellCmds)))
    }
  }
}

// Run Phase1: stage templates, render, apply injections
//
// Each parallel render branch returns `result<option<renderSlot>, string>`
// rather than mutating shared arrays. `Promise.all` preserves input order
// (JS spec guarantee), so the sequential collection pass below walks
// results[i] in template-source order. Staging writes stay inside the
// parallel branches because they target unique files; on any error the
// entire staging directory is removed.
let run: (
  ~templates: array<template>,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~preResolvedTargets: array<TemplateRenderer.resolvedTarget> =?,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<phase1Result, phase1Error>> = async (
  ~templates as _templates,
  ~context as _context,
  ~outputDir as _outputDir,
  ~conflictDecisions as _conflictDecisions,
  ~preResolvedTargets as _preResolvedTargets=[],
  ~shellConfig,
  ~fs,
  ~path,
  ~pathSecurity,
  ~ejs as _ejs,
  ~process,
) => {
  let ts = Date.now()->Float.toInt->Int.toString
  let tmpDir = await fs.makeStagingDir("blueprint-" ++ ts ++ "-")
  await EngineLifecycle.touchHeartbeat(~fs, ~stagingDir=tmpDir, ~path)
  switch await Staging.create(~tmpDir, ~fs) {
  | Error(message) =>
    Error({stagingDir: "", message: "Failed to create staging dir: " ++ message})
  | Ok(stagingDir) =>
    let renderOps = _templates->Array.map(async tmpl => {
      switch await _prepareTemplate(
        ~template=tmpl,
        ~context=_context,
        ~outputDir=_outputDir,
        ~conflictDecisions=_conflictDecisions,
        ~preResolvedTargets=_preResolvedTargets,
        ~shellConfig,
        ~fs,
        ~path,
        ~pathSecurity,
        ~ejs=_ejs,
        ~process,
      ) {
      | Error(e) => Error(e)
      | Ok(None) => Ok(None)
      | Ok(Some((sourcePath, targetPath, renderedBody, shellCmds))) =>
        switch await Staging.writeStagedFile(
          ~stagingDir,
          ~targetPath,
          ~renderedBody,
          ~path,
          ~pathSecurity,
          ~fs,
        ) {
        | Error(message) => Error("Failed to write staged file: " ++ message)
        | Ok() => {
            await EngineLifecycle.touchHeartbeat(~fs, ~stagingDir, ~path)
            Ok(Some({sourcePath, targetPath, shellCmds}))
          }
        }
      }
    })

    let results = await Promise.all(renderOps)

    // Sequential collection in source order — deterministic.
    // First error encountered in template order wins; subsequent slots are skipped.
    let renderedFiles: array<(string, string)> = []
    let shellCommands: array<shellCommand> = []
    let firstError: ref<option<string>> = ref(None)

    results->Array.forEach(result => {
      switch (firstError.contents, result) {
      | (Some(_), _) => ()
      | (None, Error(e)) => firstError.contents = Some(e)
      | (None, Ok(None)) => ()
      | (None, Ok(Some({sourcePath, targetPath, shellCmds}))) =>
        let _ = renderedFiles->Array.push((sourcePath, targetPath))
        shellCmds->Array.forEach(cmd => {
          let _ = shellCommands->Array.push(cmd)
        })
      }
    })

    switch firstError.contents {
    | Some(msg) =>
      await Staging.removeStagingDir(stagingDir, ~fs)
      Error({stagingDir, message: msg})
    | None => Ok({stagingDir, renderedFiles, shellCommands})
    }
  }
}
