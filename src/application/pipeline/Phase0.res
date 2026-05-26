// Phase0: Prompt collection + conflict detection
// Mirrors Go version's phase0/phase0.go

open Discovery

type conflictFile = {
  sourcePath: string,
  targetPath: string,
}

type phase0Result = {
  resolvedAttributes: dict<string>, // merged CLI + prompt answers
  conflicts: array<conflictFile>,
}

// Check if a file exists at target path
let _checkFileConflict: (
  ~sourcePath: string,
  ~targetPath: string,
  ~outputDir: string,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<option<conflictFile>> = async (~sourcePath, ~targetPath, ~outputDir, ~fs, ~path) => {
  let fullTargetPath = path.join(outputDir, targetPath)
  let exists = await fs.fileExists(fullTargetPath)

  if exists {
    Some({sourcePath, targetPath: fullTargetPath})
  } else {
    None
  }
}

// Detect conflicts for all templates with "to" directive
let detectConflicts: (
  ~templates: array<Template.template>,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<array<conflictFile>> = async (~templates, ~outputDir, ~force as _force, ~fs, ~path) => {
  // Collect all To directive checks as a flat array.
  // unless_exists templates are intentionally excluded from conflict detection,
  // because existing target files should be silently skipped.
  let toChecks =
    templates->Array.reduce([], (acc, tmpl) => {
      let hasUnlessExists = tmpl.directives->Array.some(d => {
        switch d {
        | Template.UnlessExists => true
        | _ => false
        }
      })

      if hasUnlessExists {
        acc
      } else {
        let found = tmpl.directives->Array.filterMap(d => {
          switch d {
          | To(path) => Some((tmpl.sourcePath, path))
          | _ => None
          }
        })
        Array.concat(acc, found)
      }
    })

  // Build an array of promises for existence checks
  let checkPromises: array<promise<option<conflictFile>>> =
    toChecks->Array.map(((sourcePath, targetPath)) => {
      let fullTarget = path.join(outputDir, targetPath)
      fs.fileExists(fullTarget)->Promise.then(exists =>
        if exists {
          Promise.resolve(Some({sourcePath, targetPath: fullTarget}))
        } else {
          Promise.resolve(None)
        }
      )
    })

  // Await all promises and filter out None values
  let results = await Promise.all(checkPromises)
  let allConflicts: array<conflictFile> = []
  results->Array.forEach(opt => {
    switch opt {
    | Some(cf) => allConflicts->Array.push(cf)->ignore
    | None => ()
    }
  })
  allConflicts
}

// Run Phase0: resolve prompts and detect conflicts
let run: (
  ~io: Ports.interactiveIO,
  ~generator: generator,
  ~context: Context.context,
  ~outputDir: string,
  ~force: bool,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<phase0Result, string>> = async (
  ~io,
  ~generator,
  ~context,
  ~outputDir,
  ~force,
  ~fs,
  ~path,
) => {
  // Get manifest prompts
  let prompts = switch generator.manifest {
  | Some(m) => m.prompts
  | None => None
  }

  // Convert attributes to plain strings for PromptResolver
  let baseContext = Dict.make()
  context.attributes->Dict.toArray->Array.forEach(((k, v)) => {
    switch v {
    | Scalar(s) => Dict.set(baseContext, k, s)
    | Values(arr) => Dict.set(baseContext, k, arr->Array.join(","))
    }
  })

  let resolvedAttributesResult = switch prompts {
  | Some(ps) if Array.length(ps) > 0 =>
    await PromptResolver.resolve(~io, ~prompts=ps, ~force, ~baseContext)
  | _ => Ok(Dict.make())
  }

  switch resolvedAttributesResult {
  | Ok(resolvedAttributes) => {
      // Detect file conflicts
      let conflicts = await detectConflicts(~templates=generator.templates, ~outputDir, ~force, ~fs, ~path)
      Ok({resolvedAttributes, conflicts})
    }
  | Error(PromptResolver.EvaluationError({prompt, field, message})) =>
    Error(
      "Prompt evaluation error [" ++ prompt ++ "." ++ field ++ "]: " ++ message,
    )
  | Error(PromptResolver.ValidationConfigError({prompt, message})) =>
    Error("Prompt validation config error [" ++ prompt ++ "]: " ++ message)
  }
}
