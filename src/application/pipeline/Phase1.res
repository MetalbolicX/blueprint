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

// Re-exported alias so tests + external callers using `Phase1.resolveTargetPath` keep compiling.
let resolveTargetPath = TemplateRenderer.resolveTargetPath

let _renderTemplate: (
  ~template: template,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
) => promise<result<option<(string, string, string, array<shellCommand>)>, string>> = async (
  ~template,
  ~context,
  ~outputDir,
  ~conflictDecisions,
  ~shellConfig,
  ~fs,
  ~path,
  ~process,
) => {
  let renderResult = await TemplateRenderer.render(
    ~template,
    ~context,
    ~outputDir,
    ~conflictDecisions,
    ~fs,
    ~path,
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
let run: (
  ~templates: array<template>,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
) => promise<result<phase1Result, phase1Error>> = async (
  ~templates as _templates,
  ~context as _context,
  ~outputDir as _outputDir,
  ~conflictDecisions as _conflictDecisions,
  ~shellConfig,
  ~fs,
  ~path,
  ~process,
) => {
  let effectiveShellConfig = shellConfig
  let stagingDir = fs.makeStagingDir()

  let mkdirResult: result<unit, phase1Error> = try {
    let _ = await fs.mkdir(stagingDir, ~options={recursive: true})
    Ok()
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => "Failed to create staging dir: " ++ m
    | None => "Failed to create staging dir"
    }
    Error({stagingDir, message: msg})
  }

  switch mkdirResult {
  | Error(err) => Error(err)
  | Ok() =>
    let renderedFiles: array<(string, string)> = []
    let shellCommands: array<shellCommand> = []
    let errorRef: ref<option<phase1Error>> = ref(None)

    let renderOps = _templates->Array.map(async tmpl => {
      switch await _renderTemplate(
        ~template=tmpl,
        ~context=_context,
        ~outputDir=_outputDir,
        ~conflictDecisions=_conflictDecisions,
        ~shellConfig=effectiveShellConfig,
        ~fs,
        ~path,
        ~process,
      ) {
      | Error(e) =>
        errorRef.contents = Some({stagingDir, message: e})
      | Ok(None) => ()
      | Ok(Some((sourcePath, targetPath, renderedBody, shellCmds))) =>
        let stagedPath = path.join(stagingDir, targetPath)
        let stagedDir = path.dirname(stagedPath)
        try {
          let _ = await fs.mkdir(stagedDir, ~options={recursive: true})
          await fs.writeFile(stagedPath, renderedBody)
          let _ = renderedFiles->Array.push((sourcePath, targetPath))
          shellCmds->Array.forEach(cmd => {
            let _ = shellCommands->Array.push(cmd)
          })
        } catch {
        | JsExn(obj) =>
          let msg = switch JsExn.message(obj) {
          | Some(m) => m
          | None => "Write failed"
          }
          errorRef.contents = Some({stagingDir, message: "Failed to write staged file: " ++ msg})
        }
      }
    })

    let _ = await Promise.all(renderOps)

    switch errorRef.contents {
    | Some(err) =>
      try {
        await fs.rm(stagingDir, ~options={recursive: true})
      } catch {
      | _ => ()
      }
      Error(err)
    | None => Ok({stagingDir, renderedFiles, shellCommands})
    }
  }
}
