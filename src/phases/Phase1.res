// Phase1: Staging, rendering, injection dispatch, shell queue
// Templates are rendered to a temp staging directory
// Mirrors Go version's phase1/phase1.go

open Bindings
open Templates

type phase1Result = {
  stagingDir: string,
  renderedFiles: array<(string, string)>,  // (source, target) pairs
  shellCommands: array<shellCommand>,
}

type phase1Error = {
  stagingDir: string,
  message: string,
}

// Resolve target path from "to" directive using context
let resolveTargetPath: (Template.directive, Context.context) => option<string> = (directive, ctx) => {
  switch directive {
  | To(path) => {
      // Render the path template with context
      let data = Js.Dict.empty()
      Js.Dict.set(data, "name", ctx.nameVariants.name)
      Js.Dict.set(data, "Name", ctx.nameVariants.Name)
      Js.Dict.set(data, "names", ctx.nameVariants.names)
      Js.Dict.set(data, "Names", ctx.nameVariants.Names)
      Js.Dict.set(data, "cwd", ctx.cwd)
      Js.Dict.set(data, "actionfolder", ctx.actionfolder)

      // Add attributes
      ctx.attributes->Js.Dict.entries->Js.Array.forEach(((k, v)) => {
        Js.Dict.set(data, k, v)
      })

      try {
        let rendered = Bindings.Ejs.render(path, data, ())
        Some(rendered)
      } catch {
      | _ => None
      }
    }
  | _ => None
  }
}

// Render a single template
let renderTemplate: (
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
      let targetPathOpt = template.directives->Js.Array.find(d => {
        switch d {
        | To(_) => true
        | _ => false
        }
      })->Option.flatMap(d => resolveTargetPath(d, context))

      let shellCmds = template.directives->Js.Array.filterMap(d => {
        switch d {
        | Sh(cmd) => Some({ command: cmd, sourcePath: template.sourcePath })
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
  ~templates,
  ~context,
  ~outputDir,
  ~conflictDecisions,
) => {
  let stagingDir = Os.makeStagingDir()

  // Create staging directory
  try {
    await Fs.mkdir(stagingDir, ~options={recursive: true})
  } catch {
  | Js.Exn.Error(obj) =>
    let msg = switch Js.Exn.message(obj) {
    | Some(m) => "Failed to create staging dir: " ++ m
    | None => "Failed to create staging dir"
    }
    return Promise.resolve(Error({ stagingDir: stagingDir, message: msg }))
  }

  let renderedFiles = Js.Array.empty()
  let shellCommands = Js.Array.empty()

  // Process each template
  try {
    templates->Js.Array.forEach(async tmpl => {
      let result = await renderTemplate(~template=tmpl, ~context)

      switch result {
      | Ok((sourcePath, targetPath, renderedBody, cmds)) => {
          // Check if this file has a conflict decision
          let shouldWrite = switch conflictDecisions {
          | Some(decisions) =>
            switch decisions->Js.Array.find(d => d.targetPath == targetPath) {
            | Some(d) => d.overwrite
            | None => true
            }
          | None => true
          }

          if shouldWrite {
            // Write to staging dir
            let stagedPath = Node.Path.join(stagingDir, targetPath)

            // Ensure parent dir exists
            let parentDir = Node.Path.dirname(stagedPath)
            await Fs.mkdir(parentDir, ~options={recursive: true})

            // Write rendered content
            await Fs.writeFile(stagedPath, renderedBody, ~options={encoding: "utf8"})

            Js.Array.push((sourcePath, targetPath), renderedFiles)
          }

          // Collect shell commands
          cmds->Js.Array.forEach(c => Js.Array.push(c, shellCommands))
        }
      | Error(_) => ()
      }
    })

    Ok({ stagingDir: stagingDir, renderedFiles: renderedFiles, shellCommands: shellCommands })
  } catch {
  | Js.Exn.Error(obj) =>
    let msg = switch Js.Exn.message(obj) {
    | Some(m) => "Phase1 error: " ++ m
    | None => "Phase1 error"
    }
    Error({ stagingDir: stagingDir, message: msg })
  }
}