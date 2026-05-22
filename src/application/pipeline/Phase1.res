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

// Lookup a tool by name in the shell config
let _findToolByName: (array<Config.shellTool>, string) => option<Config.shellTool> = (
  tools,
  name,
) => {
  tools->Array.find(tool => tool.name == name)
}

// Lookup a script by name in the shell config
let _findScriptByName: (array<Config.scriptDef>, string) => option<Config.scriptDef> = (
  scripts,
  name,
) => {
  scripts->Array.find(script => script.name == name)
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
let _hasUnlessExists: template => bool = template => {
  template.directives->Array.some(d => {
    switch d {
    | UnlessExists => true
    | _ => false
    }
  })
}

let _loadTemplateBodyFromDirective: template => promise<result<template, string>> = async template => {
  switch template.directives->Array.find(d => {
    switch d {
    | From(_) => true
    | _ => false
    }
  }) {
  | Some(From(fromPath)) => {
      let baseDir = Path.dirname(template.sourcePath)
      let resolvedPath = if Path.isAbsolute(fromPath) {
        fromPath
      } else {
        Path.join(baseDir, fromPath)
      }

      try {
        let externalBody = await Fs.readFile(resolvedPath)
        Ok({...template, body: externalBody})
      } catch {
      | JsExn(obj) =>
        let msg = switch JsExn.message(obj) {
        | Some(m) => m
        | None => "Read failed"
        }
        Error("Failed to read 'from' template " ++ resolvedPath ++ ": " ++ msg)
      }
    }
  | _ => Ok(template)
  }
}

let _collectShellCommands: (template, option<Config.shellConfig>) => array<shellCommand> = (
  template,
  shellConfig,
) => {
  template.directives->Array.filterMap(d => {
    switch d {
    | Fetch(url) =>
      // Fetch directive: Phase2 handles the actual fetching
      Some({target: Fetch(url), sourcePath: template.sourcePath})
    | Tool(name) => {
        // Tool directive: lookup in shellConfig tools
        let tools = switch shellConfig {
        | Some(cfg) => cfg.tools->Option.getOr([])
        | None => []
        }
        switch _findToolByName(tools, name) {
        | Some(toolDef) =>
          Some({target: ToolCall({name, toolDef, sourcePath: template.sourcePath}), sourcePath: template.sourcePath})
        | None =>
          // Tool not found - we'll collect error but Phase1 doesn't fail the whole pipeline
          // Phase2 will report the error when trying to execute
          Some({target: InlineCommand("tool-not-found: " ++ name), sourcePath: template.sourcePath})
        }
      }
    | Sh(rawString) =>
      // sh: directives are legacy — exact-match validation in Phase2
      Some({target: InlineCommand(rawString), sourcePath: template.sourcePath})
    | Script(name) => {
        // Script directive: lookup in shellConfig scripts
        let scripts = switch shellConfig {
        | Some(cfg) => cfg.scripts->Option.getOr([])
        | None => []
        }
        switch _findScriptByName(scripts, name) {
        | Some(scriptDef) =>
          let baseDir = Path.dirname(template.sourcePath)
          let resolvedPath = Path.isAbsolute(scriptDef.path)
            ? scriptDef.path
            : Path.join(baseDir, scriptDef.path)
          Some({target: ScriptFile(resolvedPath), sourcePath: template.sourcePath})
        | None =>
          Some({target: InlineCommand("script-not-found: " ++ name), sourcePath: template.sourcePath})
        }
      }
    | _ => None
    }
  })
}

let _renderTemplate: (
  ~template: template,
  ~context: Context.context,
  ~outputDir: string,
  ~shellConfig: option<Config.shellConfig>,
) => promise<result<option<(string, string, string, array<shellCommand>)>, string>> = async (
  ~template,
  ~context,
  ~outputDir,
  ~shellConfig,
) => {
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

  switch targetPathOpt {
  | None => Error("No 'to' directive found in template: " ++ template.sourcePath)
  | Some(targetPath) => {
      if _hasUnlessExists(template) {
        let finalTargetPath = Path.join(outputDir, targetPath)
        let exists = await Fs.fileExists(finalTargetPath)
        if exists {
          Ok(None)
        } else {
          switch await _loadTemplateBodyFromDirective(template) {
          | Error(e) => Error(e)
          | Ok(templateToRender) => {
              let renderCtx = Context.toRenderContext(context)
              switch Renderer.render(templateToRender, renderCtx) {
              | Ok(renderedBody) => {
                  let shellCmds = _collectShellCommands(template, shellConfig)
                  Ok(Some((template.sourcePath, targetPath, renderedBody, shellCmds)))
                }
              | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
              }
            }
          }
        }
      } else {
        switch await _loadTemplateBodyFromDirective(template) {
        | Error(e) => Error(e)
        | Ok(templateToRender) => {
            let renderCtx = Context.toRenderContext(context)
            switch Renderer.render(templateToRender, renderCtx) {
            | Ok(renderedBody) => {
                let shellCmds = _collectShellCommands(template, shellConfig)
                Ok(Some((template.sourcePath, targetPath, renderedBody, shellCmds)))
              }
            | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
            }
          }
        }
      }
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
) => promise<result<phase1Result, phase1Error>> = async (
  ~templates as _templates,
  ~context as _context,
  ~outputDir as _outputDir,
  ~conflictDecisions as _conflictDecisions,
  ~shellConfig,
) => {
  let effectiveShellConfig = shellConfig
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
      switch await _renderTemplate(~template=tmpl, ~context=_context, ~outputDir=_outputDir, ~shellConfig=effectiveShellConfig) {
      | Error(e) =>
        errorRef.contents = Some({stagingDir, message: e})
      | Ok(None) => ()
      | Ok(Some((sourcePath, targetPath, renderedBody, shellCmds))) =>
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
