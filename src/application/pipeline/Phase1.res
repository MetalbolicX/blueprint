// Phase1: Staging, rendering, injection dispatch, shell queue
// Templates are rendered to a temp staging directory
// Mirrors Go version's phase1/phase1.go

open Bindings
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

// Resolve target path from "to" directive using context
let resolveTargetPath: (Template.directive, Context.context) => option<string> = (
  directive,
  ctx,
) => {
  switch directive {
  | To(path) => {
      // Render the path template with context
      let data = Dict.make()
      Dict.set(data, "name", ctx.nameVariants.name)
      Dict.set(data, "Name", ctx.nameVariants.pascalName)
      Dict.set(data, "names", ctx.nameVariants.names)
      Dict.set(data, "Names", ctx.nameVariants.pluralPascalName)
      Dict.set(data, "cwd", ctx.cwd)
      Dict.set(data, "actionfolder", ctx.actionfolder)

      // Add attributes
      ctx.attributes
      ->Dict.toArray
      ->Array.forEach(((k, v)) => {
        Dict.set(data, k, v)
      })

      try {
        let rendered = Bindings.Ejs.render(path, data)
        Some(rendered)
      } catch {
      | _ => None
      }
    }
  | _ => None
  }
}

// Render a single template
let _renderTemplate: (
  ~template: template,
  ~context: Context.context,
) => promise<result<(string, string, string, array<shellCommand>), string>> = async (
  ~template,
  ~context,
) => {
  // Build render context for EJS
  let renderCtx = Context.toRenderContext(context)

  // Render body
  switch Renderer.render(template, renderCtx) {
  | Ok(renderedBody) => {
      // Find "to" directive for target path
      let targetPathOpt =
        template.directives
        ->Array.find(d => {
          switch d {
          | To(_) => true
          | _ => false
          }
        })
        ->Option.flatMap(d => resolveTargetPath(d, context))

      let shellCmds = template.directives->Array.filterMap(d => {
        switch d {
        | Sh(rawString) =>
          if Frontmatter.isFileReference(rawString) {
            let templateDir = Path.dirname(template.sourcePath)
            let resolvedPath = Path.resolve(templateDir, rawString)
            Some({target: ScriptFile(resolvedPath), sourcePath: template.sourcePath})
          } else {
            Some({target: InlineCommand(rawString), sourcePath: template.sourcePath})
          }
        | _ => None
        }
      })

      switch targetPathOpt {
      | Some(targetPath) => Ok((template.sourcePath, targetPath, renderedBody, shellCmds))
      | None => Error("No 'to' directive found in template: " ++ template.sourcePath)
      }
    }
  | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
  }
}

// Run Phase1: stage templates, render, apply injections
let run: (
  ~templates: array<template>,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
) => promise<result<phase1Result, phase1Error>> = async (
  ~templates as _templates,
  ~context as _context,
  ~outputDir as _outputDir,
  ~conflictDecisions as _conflictDecisions,
) => {
  let stagingDir = Os.makeStagingDir()

  let mkdirResult: result<unit, phase1Error> = try {
    let _ = await Fs.mkdir(stagingDir, ~options={recursive: true})
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
      switch await _renderTemplate(~template=tmpl, ~context=_context) {
      | Error(e) =>
        errorRef.contents = Some({stagingDir, message: e})
      | Ok((sourcePath, targetPath, renderedBody, shellCmds)) =>
        let stagedPath = Path.join(stagingDir, targetPath)
        let stagedDir = Path.dirname(stagedPath)
        try {
          let _ = await Fs.mkdir(stagedDir, ~options={recursive: true})
          await Fs.writeFile(stagedPath, renderedBody)
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
        await Fs.rm(stagingDir, ~options={recursive: true})
      } catch {
      | _ => ()
      }
      Error(err)
    | None => Ok({stagingDir, renderedFiles, shellCommands})
    }
  }
}
