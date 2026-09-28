// TemplateRenderer: target-path resolution, From body loading, render, injection, skip-decisions.
// Owns the render/injection concerns of Phase1; Phase1 stitches it with ShellQueue for the full tuple.

open Template

type renderedOutput = {
  sourcePath: string,
  targetPath: string,
  renderedBody: string,
}

type stageVerdict =
  | StageProceed
  | StageSkip

let resolveTargetPath: (~ejs: Ports.ejs, Template.directive, Context.context) => result<string, string> = (
  ~ejs,
  directive,
  ctx,
) => {
  switch directive {
  | To(path) => {
      // Render the path template with context.
      // WS4: cwd and actionfolder are intentionally NOT injected into the
      // template-facing data. They remain on the internal `context` type for
      // shell exec but templates must never see host filesystem paths.
      let data = Dict.make()
      Dict.set(data, "name", ctx.nameVariants.name)
      Dict.set(data, "Name", ctx.nameVariants.pascalName)
      Dict.set(data, "names", ctx.nameVariants.names)
      Dict.set(data, "Names", ctx.nameVariants.pluralPascalName)

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
      Dict.set(data, "h", FuncMap.makeHelpersDict()->Obj.magic)

      switch ejs.renderString(~template=path, ~context=data) {
      | Ok(rendered) => Ok(rendered)
      | Error(msg) => Error(msg)
      }
    }
  | _ => Error("No 'to' directive")
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
    // Read existing content; distinguish ENOENT (file truly missing) from real errors.
    let readResult = try {
      Ok(await fs.readFile(finalTargetPath, ~options={encoding: "utf8"}))
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "unknown error"
      }
      let code = switch Obj.magic(obj)["code"] {
      | Some(c) => c
      | None => ""
      }
      if code == "ENOENT" {
        Error("ENOENT")
      } else {
        Error("Read failed for " ++ finalTargetPath ++ ": " ++ msg)
      }
    | _ => Error("Read failed for " ++ finalTargetPath)
    }

    switch readResult {
    | Error("ENOENT") =>
      // File truly doesn't exist — only certain directives can cope with that.
      switch directive {
      | Inject(_) | Before(_) | After(_) | AtLine(_) | SkipIf(_) =>
        Error("Target file not found: " ++ finalTargetPath)
      | _ => Ok(renderedBody) // prepend/append can work with no existing content
      }
    | Error(msg) => Error(msg) // Real filesystem error — propagate verbatim.
    | Ok(existingContent) =>
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

// Resolve template body from inline value or `from:` directive file load
let resolveTemplateBody = async (template, ~fs: Ports.fileSystem, ~path: Ports.path) => {
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
          Ok(externalBody)
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
  | _ => Ok(template.body)
  }
}

// Validate staging conditions: path security, conflict decisions, unlessExists
let stageAndValidate = async (template, ~targetPath: string, ~finalTargetPath: string, ~outputDir: string, ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>, ~fs: Ports.fileSystem, ~path: Ports.path) => {
  let isWithin = await PathSecurity.isWithinTree(finalTargetPath, outputDir, path, fs)
  if !isWithin {
    Error("Rendered 'to' path escapes output tree: " ++ targetPath)
  } else {
    let skipFromDecision = switch conflictDecisions {
    | Some(decisions) =>
      decisions->Array.some(d => d.targetPath == finalTargetPath && !d.overwrite)
    | None => false
    }

    if skipFromDecision {
      Ok(StageSkip)
    } else if hasUnlessExists(template) {
      let exists = await fs.fileExists(finalTargetPath)
      if exists {
        Ok(StageSkip)
      } else {
        Ok(StageProceed)
      }
    } else {
      Ok(StageProceed)
    }
  }
}

// Render a template end-to-end (resolve target, body load, render, validate, inject).
// Returns None when the template should be skipped (conflict-decision-skip or unless-exists hit).
let render: (
  ~template: template,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<option<renderedOutput>, string>> = async (
  ~template,
  ~context,
  ~outputDir,
  ~conflictDecisions,
  ~fs,
  ~path,
  ~ejs,
  ~process as _,
) => {
  // 1. Resolve target path
  let targetPathResult =
    template.directives
    ->Array.find(d => {
      switch d {
      | To(_) => true
      | _ => false
      }
    })
    ->Option.map(d => resolveTargetPath(~ejs, d, context))

  switch targetPathResult {
  | None => Error("No 'to' directive found in template: " ++ template.sourcePath)
  | Some(Error(e)) =>
    Error("Failed to render 'to' path in template " ++ template.sourcePath ++ ": " ++ e)
  | Some(Ok(targetPath)) => {
    let finalTargetPath = path.join(outputDir, targetPath)

    // 2. Resolve template body (inline or from: directive file)
    switch await resolveTemplateBody(template, ~fs, ~path) {
    | Error(e) => Error(e)
    | Ok(resolvedBody) =>
      // 3. Render the template body with context
      let provenancePath = path.join(path.dirname(template.sourcePath), ".blueprint-provenance")
      let hasProvenance = await fs.fileExists(provenancePath)
      let unsafe = hasProvenance && EjsSafety.isUnsafe(resolvedBody)
      if unsafe {
        Error(
          "Registry-installed template was blocked by the provenance gate: " ++ template.sourcePath ++
          ". Unsafe EJS tags (<% or <%-) are not allowed; inspect the template before removing its .blueprint-provenance marker.",
        )
      } else {
      let renderCtx = Context.toRenderContext(context)
      switch Renderer.render({...template, body: resolvedBody}, renderCtx) {
      | Error(e) => Error("Failed to render template " ++ template.sourcePath ++ ": " ++ e)
      | Ok(renderedBody) =>
        // 4. Validate staging (path security, conflict decisions, unlessExists)
        switch await stageAndValidate(
          template,
          ~targetPath,
          ~finalTargetPath,
          ~outputDir,
          ~conflictDecisions,
          ~fs,
          ~path,
        ) {
        | Ok(StageSkip) => Ok(None)
        | Error(e) => Error(e)
        | Ok(StageProceed) => {
            // 5. Apply injection when template requires an existing target file
            let finalRenderedBody =
              if hasUnlessExists(template) {
                Ok(renderedBody)
              } else if requiresExistingTarget(template) {
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
        }
      }
      }
    }
    }
  }
}
