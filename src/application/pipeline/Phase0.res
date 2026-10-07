// Phase0: Prompt collection + conflict detection
// Mirrors Go version's phase0/phase0.go

open Discovery
open Resolver

type conflictFile = {
  sourcePath: string,
  targetPath: string,
}

type phase0Result = {
  resolvedAttributes: dict<string>, // merged CLI + prompt answers
  conflicts: array<conflictFile>,
  resolvedTargets: array<TemplateRenderer.resolvedTarget>,
}

// Check if a file exists at target path

// Detect conflicts for all templates with "to" directive
let resolveRenderedTargetsAndDetectConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
  ~ejs: Ports.ejs,
  ~attributes: dict<string>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<(array<conflictFile>, array<TemplateRenderer.resolvedTarget>), string>> = async (~templates, ~outputDir, ~force as _force, ~ejs, ~attributes, ~fs, ~path, ~pathSecurity as _pathSecurity) => {
  // Resolve every To directive once. UnlessExists targets are retained for Phase1
  // but remain excluded from conflict detection, where they are silently skipped.
  let toChecks = templates->Array.reduce([], (acc, tmpl) => {
    let hasUnlessExists = tmpl.directives->Array.some(d => {
      switch d {
      | Template.UnlessExists => true
      | _ => false
      }
    })
    let found = tmpl.directives->Array.filterMap(d =>
      switch d {
      | To(to) => Some((tmpl.sourcePath, to, hasUnlessExists))
      | _ => None
      }
    )
    Array.concat(acc, found)
  })

  let firstError: ref<option<string>> = ref(None)
  let resolvedTargets: array<TemplateRenderer.resolvedTarget> = []
  let resolvedChecks = toChecks->Array.filterMap(((sourcePath, to, unlessExists)) =>
    switch TemplateRenderer.renderTargetPath(~to, ~ejs, ~attributes) {
    | Error(msg) => {
      if firstError.contents == None {
        firstError.contents = Some("Failed to render 'to' path in template " ++ sourcePath ++ ": " ++ msg)
      }
      None
    }
    | Ok(targetPath) => {
      let fullTarget = path.join(outputDir, targetPath)
      resolvedTargets->Array.push({sourcePath, targetPath})->ignore
      if unlessExists {None} else {Some((sourcePath, fullTarget))}
    }
    }
  )
  switch firstError.contents {
  | Some(msg) => Error(msg)
  | None => {
      let checkPromises: array<promise<option<conflictFile>>> = resolvedChecks->Array.map(((sourcePath, fullTarget)) =>
        fs.fileExists(fullTarget)->Promise.then(exists =>
          if exists {
            Promise.resolve(Some({sourcePath, targetPath: fullTarget}))
          } else {
            Promise.resolve(None)
          }
        )
      )
      let results = await Promise.all(checkPromises)
      let allConflicts: array<conflictFile> = []
      results->Array.forEach(opt => {
        switch opt {
        | Some(cf) => allConflicts->Array.push(cf)->ignore
        | None => ()
        }
      })
      Ok((allConflicts, resolvedTargets))
    }
  }
}

let detectRenderedConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
  ~ejs: Ports.ejs,
  ~attributes: dict<string>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<array<conflictFile>, string>> = async (~templates, ~outputDir, ~force, ~ejs, ~attributes, ~fs, ~path, ~pathSecurity) =>
  switch await resolveRenderedTargetsAndDetectConflicts(~templates, ~outputDir, ~force, ~ejs, ~attributes, ~fs, ~path, ~pathSecurity) {
  | Error(message) => Error(message)
  | Ok((conflicts, _resolvedTargets)) => Ok(conflicts)
  }

// Run Phase0: resolve prompts and detect conflicts
let run: (
  ~io: Ports.interactiveIO,
  ~ejs: Ports.ejs,
  ~generator: generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<phase0Result, string>> = async (
  ~io,
  ~ejs,
  ~generator,
  ~context,
  ~outputDir,
  ~force,
  ~fs,
  ~path,
  ~pathSecurity,
) => {
  // Get manifest prompts
  let prompts = switch generator.manifest {
  | Some(m) => m.prompts
  | None => None
  }

  // Convert attributes to plain strings for Resolver
  let baseContext = Dict.make()
  context.attributes->Dict.toArray->Array.forEach(((k, v)) => {
    switch v {
    | Scalar(s) => Dict.set(baseContext, k, s)
    | Values(arr) => Dict.set(baseContext, k, arr->Array.join(","))
    }
  })

  let resolvedAttributesResult = switch prompts {
  | Some(ps) if Array.length(ps) > 0 =>
    await resolve(~io, ~ejs, ~prompts=ps, ~force, ~baseContext)
  | _ => Ok(Dict.make())
  }

  switch resolvedAttributesResult {
  | Ok(resolvedAttributes) => {
      // Prompt answers override the already-stringified base context for target rendering.
      let mergedAttributes = Dict.make()
      baseContext->Dict.toArray->Array.forEach(((k, v)) => Dict.set(mergedAttributes, k, v))
      resolvedAttributes->Dict.toArray->Array.forEach(((k, v)) => Dict.set(mergedAttributes, k, v))
      switch await resolveRenderedTargetsAndDetectConflicts(
        ~templates=generator.templates,
        ~outputDir,
        ~force,
        ~ejs,
        ~attributes=mergedAttributes,
        ~fs,
        ~path,
        ~pathSecurity,
      ) {
      | Error(e) => Error(e)
      | Ok((conflicts, resolvedTargets)) => Ok({resolvedAttributes, conflicts, resolvedTargets})
      }
    }
  | Error(Expression.EvaluationError({prompt, field, message})) =>
    Error(
      "Prompt evaluation error [" ++ prompt ++ "." ++ field ++ "]: " ++ message,
    )
  | Error(Expression.ValidationConfigError({prompt, message})) =>
    Error("Prompt validation config error [" ++ prompt ++ "]: " ++ message)
  | Error(Expression.MissingOptionsError({prompt, message})) =>
    Error("Prompt configuration error [" ++ prompt ++ "]: " ++ message)
  }
}
