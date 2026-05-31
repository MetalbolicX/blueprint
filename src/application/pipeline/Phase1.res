// Phase1: Staging, rendering, injection dispatch, shell queue
// Templates are rendered to a temp staging directory
// Mirrors Go version's phase1/phase1.go

open Template
open FuncMap

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

      // Add attributes (convert attrValue to string)
      ctx.attributes
      ->Dict.toArray
      ->Array.forEach(((k, v)) => {
        let strValue = switch v {
        | Context.Scalar(s) => s
        | Context.Values(arr) => arr->Array.join(",")
        }
        Dict.set(data, k, strValue)
      })

      // Add h helper functions (pascalCase, kebabCase, etc.)
      let helpers = makeHelpers()
      let hObj = Dict.make()
      Dict.set(hObj, "pascalCase", helpers.pascalCase->Obj.magic)
      Dict.set(hObj, "camelCase", helpers.camelCase->Obj.magic)
      Dict.set(hObj, "kebabCase", helpers.kebabCase->Obj.magic)
      Dict.set(hObj, "snakeCase", helpers.snakeCase->Obj.magic)
      Dict.set(hObj, "upper", helpers.upper->Obj.magic)
      Dict.set(hObj, "lower", helpers.lower->Obj.magic)
      Dict.set(hObj, "trim", helpers.trim->Obj.magic)
      Dict.set(hObj, "title", helpers.title->Obj.magic)
      Dict.set(data, "h", hObj->Obj.magic)

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

// Check if template has directives that require an existing target file
let _requiresExistingTarget: template => bool = template => {
  template.directives->Array.some(d => {
    switch d {
    | Inject(_) | After(_) | Before(_) | AtLine(_) | Prepend | Append | SkipIf(_) => true
    | _ => false
    }
  })
}

// Apply injection directives to rendered content
let _applyInjection: (
  ~renderedBody: string,
  ~template: template,
  ~finalTargetPath: string,
  ~fs: Ports.fileSystem,
) => promise<result<string, string>> = async (~renderedBody, ~template, ~finalTargetPath, ~fs) => {
  // Find the injection directive (before, after, inject, prepend, append, atLine)
  let injectionDirective = template.directives->Array.find(d => {
    switch d {
    | Inject(_) | After(_) | Before(_) | AtLine(_) | Prepend | Append => true
    | _ => false
    }
  })

  switch injectionDirective {
  | None => Ok(renderedBody) // no injection needed
  | Some(directive) =>
    // Read existing content from target file
    let fileExists = ref(true)
    let existingContent = try {
      await fs.readFile(finalTargetPath, ~options={encoding: "utf8"})
    } catch {
    | _ =>
      fileExists := false
      ""
    }

    // For inject/before/after/atLine/skipIf, file must exist
    if !fileExists.contents {
      switch directive {
      | Inject(_) | Before(_) | After(_) | AtLine(_) | SkipIf(_) =>
        Error("Target file not found: " ++ finalTargetPath)
      | _ => Ok(existingContent) // prepend/append can work with empty content
      }
    } else {
      // Apply injection
      switch Injection.apply(
        ~existingContent,
        ~renderedContent=renderedBody,
        ~directive,
        ~allDirectives=template.directives,
      ) {
      | Error(e) => Error("Injection failed for " ++ finalTargetPath ++ ": " ++ e)
      | Ok({content, applied: _}) => Ok(content)
      }
    }
  }
}

let _loadTemplateBodyFromDirective: (
  template,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<template, string>> = async (template, ~fs, ~path) => {
  switch template.directives->Array.find(d => {
    switch d {
    | From(_) => true
    | _ => false
    }
  }) {
  | Some(From(fromPath)) => {
      let templateDir = path.dirname(template.sourcePath)
      let resolvedPath = if path.isAbsolute(fromPath) {
        fromPath
      } else {
        path.join(templateDir, fromPath)
      }

      let isWithin = await PathSecurity.isWithinTree(resolvedPath, templateDir, path, fs)
      if !isWithin {
        Error("Invalid 'from' path outside template tree: " ++ fromPath)
      } else {

        try {
          let externalBody = await fs.readFile(resolvedPath, ~options={encoding: "utf8"})
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
    }
  | _ => Ok(template)
  }
}

let _collectShellCommands: (
  template,
  option<Config.shellConfig>,
  ~actionfolder: string,
  ~path: Ports.path,
  ~process: Ports.process,
) => result<array<shellCommand>, string> = (
  template,
  shellConfig,
  ~actionfolder,
  ~path,
  ~process,
) => {
  let commands: array<shellCommand> = []
  let errorRef: ref<option<string>> = ref(None)

  template.directives->Array.forEach(d => {
    switch errorRef.contents {
    | Some(_) => ()
    | None =>
      switch d {
      | Fetch(url) => {
          let _ = commands->Array.push({target: Fetch(url), sourcePath: template.sourcePath})
        }
      | Tool(name) => {
          let tools = switch shellConfig {
          | Some(cfg) => cfg.tools->Option.getOr([])
          | None => []
          }
          switch _findToolByName(tools, name) {
          | Some(toolDef) =>
            let _ = commands->Array.push({
              target: ToolCall({name, toolDef, sourcePath: template.sourcePath}),
              sourcePath: template.sourcePath,
            })
          | None =>
            errorRef.contents = Some("Tool not found: " ++ name ++ " (template: " ++ template.sourcePath ++ ")")
          }
        }
      | Script(name) => {
          let scripts = switch shellConfig {
          | Some(cfg) => cfg.scripts->Option.getOr([])
          | None => []
          }
          switch _findScriptByName(scripts, name) {
          | Some(scriptDef) =>
            let baseDir = if path.isAbsolute(actionfolder) {
              actionfolder
            } else {
              path.resolve(process.cwd(), actionfolder)
            }
            let resolvedPath = path.isAbsolute(scriptDef.path)
              ? scriptDef.path
              : path.join(baseDir, scriptDef.path)
            let _ = commands->Array.push({target: ScriptFile(resolvedPath), sourcePath: template.sourcePath})
          | None =>
            errorRef.contents = Some("Script not found: " ++ name ++ " (template: " ++ template.sourcePath ++ ")")
          }
        }
      | _ => ()
      }
    }
  })

  switch errorRef.contents {
  | Some(message) => Error(message)
  | None => Ok(commands)
  }
}

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
  | Some(targetPath) =>
    let finalTargetPath = path.join(outputDir, targetPath)

    // Check conflict decisions: skip files the user chose not to overwrite
    let skipFromDecision = switch conflictDecisions {
    | Some(decisions) =>
      decisions->Array.some(d => d.targetPath == finalTargetPath && !d.overwrite)
    | None => false
    }

    if skipFromDecision {
      Ok(None)
    } else if _hasUnlessExists(template) {
        let finalTargetPath = path.join(outputDir, targetPath)
        let exists = await fs.fileExists(finalTargetPath)
        if exists {
          Ok(None)
        } else {
          switch await _loadTemplateBodyFromDirective(template, ~fs, ~path) {
          | Error(e) => Error(e)
          | Ok(templateToRender) => {
              let renderCtx = Context.toRenderContext(context)
              switch Renderer.render(templateToRender, renderCtx) {
              | Ok(renderedBody) => {
                  switch _collectShellCommands(
                    template,
                    shellConfig,
                    ~actionfolder=context.actionfolder,
                    ~path,
                    ~process,
                  ) {
                  | Error(e) => Error(e)
                  | Ok(shellCmds) => Ok(Some((template.sourcePath, targetPath, renderedBody, shellCmds)))
                  }
                }
              | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
              }
            }
          }
        }
      } else {
        switch await _loadTemplateBodyFromDirective(template, ~fs, ~path) {
        | Error(e) => Error(e)
        | Ok(templateToRender) => {
            let renderCtx = Context.toRenderContext(context)
            switch Renderer.render(templateToRender, renderCtx) {
            | Ok(renderedBody) => {
                // Apply injection if template has injection directives
                let finalRenderedBody = if _requiresExistingTarget(template) {
                  switch await _applyInjection(~renderedBody, ~template, ~finalTargetPath, ~fs) {
                  | Error(e) => Error(e)
                  | Ok(injected) => Ok(injected)
                  }
                } else {
                  Ok(renderedBody)
                }
                switch finalRenderedBody {
                | Error(e) => Error(e)
                | Ok(body) =>
                  switch _collectShellCommands(
                    template,
                    shellConfig,
                    ~actionfolder=context.actionfolder,
                    ~path,
                    ~process,
                  ) {
                  | Error(e) => Error(e)
                  | Ok(shellCmds) => Ok(Some((template.sourcePath, targetPath, body, shellCmds)))
                  }
                }
              }
            | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
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
