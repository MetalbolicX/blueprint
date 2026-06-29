// TemplateRenderer: target-path resolution, From body loading, render, injection, skip-decisions.
// Owns the render/injection concerns of Phase1; Phase1 stitches it with ShellQueue for the full tuple.

open Template
open FuncMap

type renderedOutput = {
  sourcePath: string,
  targetPath: string,
  renderedBody: string,
}

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

let hasUnlessExists: template => bool = template => {
  template.directives->Array.some(d => {
    switch d {
    | UnlessExists => true
    | _ => false
    }
  })
}

let requiresExistingTarget: template => bool = template => {
  template.directives->Array.some(d => {
    switch d {
    | Inject(_) | After(_) | Before(_) | AtLine(_) | Prepend | Append | SkipIf(_) => true
    | _ => false
    }
  })
}

let applyInjection: (
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

let loadTemplateBodyFromDirective: (
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

// Render a template end-to-end (resolve target, skip-decisions, body load, render, inject).
// Returns None when the template should be skipped (conflict-decision-skip or unless-exists hit).
let render: (
  ~template: template,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
) => promise<result<option<renderedOutput>, string>> = async (
  ~template,
  ~context,
  ~outputDir,
  ~conflictDecisions,
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
  | Some(targetPath) => {
    let finalTargetPath = path.join(outputDir, targetPath)

    // WS1: reject any rendered `to:` that escapes the output tree.
    // Covers absolute paths, `..` traversal, and symlinks that resolve outside outputDir.
    // Mirrors the existing `from:` guard at TemplateRenderer.loadTemplateBodyFromDirective:149.
    let isWithin = await PathSecurity.isWithinTree(finalTargetPath, outputDir, path, fs)
    if !isWithin {
      Error("Rendered 'to' path escapes output tree: " ++ targetPath)
    } else {
      // Check conflict decisions: skip files the user chose not to overwrite
      let skipFromDecision = switch conflictDecisions {
      | Some(decisions) =>
        decisions->Array.some(d => d.targetPath == finalTargetPath && !d.overwrite)
      | None => false
      }

      if skipFromDecision {
        Ok(None)
      } else if hasUnlessExists(template) {
        let exists = await fs.fileExists(finalTargetPath)
        if exists {
          Ok(None)
        } else {
          switch await loadTemplateBodyFromDirective(template, ~fs, ~path) {
          | Error(e) => Error(e)
          | Ok(templateToRender) => {
              let renderCtx = Context.toRenderContext(context)
              switch Renderer.render(templateToRender, renderCtx) {
              | Ok(renderedBody) =>
                Ok(Some({sourcePath: template.sourcePath, targetPath, renderedBody}))
              | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
              }
            }
          }
        }
      } else {
        switch await loadTemplateBodyFromDirective(template, ~fs, ~path) {
        | Error(e) => Error(e)
        | Ok(templateToRender) => {
            let renderCtx = Context.toRenderContext(context)
            switch Renderer.render(templateToRender, renderCtx) {
            | Ok(renderedBody) => {
                // Apply injection if template has injection directives
                let finalRenderedBody = if requiresExistingTarget(template) {
                  switch await applyInjection(~renderedBody, ~template, ~finalTargetPath, ~fs) {
                  | Error(e) => Error(e)
                  | Ok(injected) => Ok(injected)
                  }
                } else {
                  Ok(renderedBody)
                }
                switch finalRenderedBody {
                | Error(e) => Error(e)
                | Ok(body) => Ok(Some({sourcePath: template.sourcePath, targetPath, renderedBody: body}))
                }
              }
            | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
            }
          }
        }
      }
    }
    }
  }
}