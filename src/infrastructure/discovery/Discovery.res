// Discovery — traverse _templates/ directory, find generators
// Follows Hygen's _templates/<generator>/<action>/ convention

open Template

type generator = {
  name: string, // directory name (e.g. "component")
  path: string, // absolute path to generator dir
  templates: array<template>, // .ejs.t files found
  manifest?: Manifest.manifest, // manifest.yaml if present
}

type generatorMeta = {
  name: string,
  path: string,
  manifest: option<Manifest.manifest>,
}

let isManifestFile: string => bool = filename => {
  filename == "manifest.yaml"
}

let maxConcurrent = 8

// Run async factories with bounded concurrency while retaining input order.
let mapBounded: (array<'a>, 'a => promise<'b>) => promise<array<'b>> = async (items, load) => {
  let length = Array.length(items)
  let cursor = ref(0)
  let results: array<option<'b>> = Array.make(~length, None)

  let rec worker = async () => {
    let index = cursor.contents
    if index < length {
      cursor := index + 1
      switch items[index] {
      | Some(item) => {
          let value = await load(item)
          results[index] = Some(value)
          await worker()
        }
      | None => await worker()
      }
    }
  }

  let workerCount = min(maxConcurrent, length)
  let workers = Array.make(~length=workerCount, ())
  let _ = await Promise.all(workers->Array.map(_ => worker()))
  results->Array.map(result => switch result {
  | Some(value) => value
  | None => JsError.throwWithMessage("mapBounded worker did not produce a result")
  })
}

let _errorMessage = (exn: exn, fallback: string): string => switch exn {
| JsExn(obj) => JsExn.message(obj)->Option.getOr(fallback)
| _ => fallback
}

let _isNotFound = (msg: string): bool =>
  String.startsWith(msg, "ENOENT:") || String.includes(msg, "no such file or directory")

// Load and parse a single template file
let _loadTemplate: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<option<template>> = async (
  ~fs,
  ~path,
  sourcePath,
) => {
  try {
    let content = await fs.readFile(sourcePath, ~options={encoding: "utf8"})
    let filename = path.basename(sourcePath)

    if isManifestFile(filename) {
      None
    } else {
      switch Frontmatter.parse(content) {
      | Ok(parsed) =>
        Some({
          sourcePath,
          directives: parsed.directives,
          body: parsed.body,
        })
      | Error(e) => {
          Console.warn("Skipping template " ++ sourcePath ++ ": " ++ e)
          None
        }
      }
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to load template " ++ sourcePath
    }
    if String.startsWith(msg, "Parse error in ") {
      Console.warn(msg)
      None
    } else if _isNotFound(msg) {
      None
    } else {
      Console.warn("Skipping template " ++ sourcePath ++ ": " ++ msg)
      None
    }
  }
}

// Load manifest.yaml from a generator directory if present.
// Fail-fast contract:
//   Ok(None)  — no manifest.yaml present (allowed)
//   Ok(Some)  — manifest present AND valid
//   Error(s)  — manifest present but failed to parse OR failed validation;
//                s is `manifest at <path> invalid: <details>`
let _loadManifest: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, string) => promise<
  result<option<Manifest.manifest>, string>,
> = async (~fs, ~path, ~yamlParser, generatorPath) => {
  let manifestPath = path.join(generatorPath, "manifest.yaml")

  let exists = await fs.fileExists(manifestPath)
  if !exists {
    Ok(None)
  } else {
    try {
      let content = await fs.readFile(manifestPath, ~options={encoding: "utf8"})
      switch Manifest.parse(~yamlParser, ~yaml=content) {
      | Ok(m) =>
        switch Manifest.validate(m) {
        | Ok() =>
          // Validate declared hook files exist relative to the generator directory.
          // Check preGenerate first, then postGenerate; short-circuit on first miss.
          switch m.hooks {
          | None => Ok(Some(m))
          | Some(h) =>
            switch h.preGenerate {
            | None => Ok(Some(m))
            | Some(hookPath) =>
              let resolved = path.join(generatorPath, hookPath)
              switch await fs.fileExists(resolved) {
              | false => Error("Hook script not found: " ++ resolved)
              | true =>
                switch h.postGenerate {
                | None => Ok(Some(m))
                | Some(hookPath2) =>
                  let resolved2 = path.join(generatorPath, hookPath2)
                  switch await fs.fileExists(resolved2) {
                  | false => Error("Hook script not found: " ++ resolved2)
                  | true => Ok(Some(m))
                  }
                }
              }
            }
          }
        | Error(errors) => {
            let details = Manifest.validationErrorsToString(errors)
            Error("manifest at " ++ manifestPath ++ " invalid: " ++ details)
          }
        }
      | Error(parseErr) => Error("manifest at " ++ manifestPath ++ " parse error: " ++ parseErr)
      }
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Failed to read manifest " ++ manifestPath
      }
      Error("manifest at " ++ manifestPath ++ " read error: " ++ msg)
    }
  }
}

// Load every template under one generator directory.
let loadGeneratorTemplates: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<array<template>> = async (
  ~fs,
  ~path,
  genPath,
) => {
  let actionEntries = try {
    await fs.readdir(genPath, ~options={withFileTypes: false})
  } catch {
  | exn =>
    let msg = _errorMessage(exn, "Failed to read directory " ++ genPath)
    if !_isNotFound(msg) {
      Console.warn("Skipping directory " ++ genPath ++ ": " ++ msg)
    }
    []
  }

  let actionTemplatePaths = await mapBounded(actionEntries, async actionName => {
    let actionPath = path.join(genPath, actionName)
    let actionStat = try {
      Some(await fs.stat(actionPath))
    } catch {
    | _ => None
    }

    switch actionStat {
    | Some(dirStat) if dirStat.isDirectory() => {
      let files = try {
        await fs.readdir(actionPath, ~options={withFileTypes: false})
      } catch {
      | exn =>
        let msg = _errorMessage(exn, "Failed to read directory " ++ actionPath)
        if !_isNotFound(msg) {
          Console.warn("Skipping directory " ++ actionPath ++ ": " ++ msg)
        }
        []
      }

      files->Array.filter(isTemplateFile)->Array.map(fname => path.join(actionPath, fname))
    }
    | _ => []
    }
  })

  let templatePaths = actionTemplatePaths->Array.reduce([], (acc, paths) => acc->Array.concat(paths))
  let loaded = await mapBounded(templatePaths, sourcePath => _loadTemplate(~fs, ~path, sourcePath))
  loaded->Array.filterMap(x => x)
}

// Discover all generators under a base directory
let discoverIn: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, string) => promise<array<generator>> = async (
  ~fs,
  ~path,
  ~yamlParser,
  baseDir,
) => {
  let exists = await fs.fileExists(baseDir)
  if !exists {
    []
  } else {
    try {
      let entries = await fs.readdir(baseDir, ~options={withFileTypes: false})

      let genPromises = entries->Array.map(async entry => {
        let genPath = path.join(baseDir, entry)
        let stat = try {
          Some(await fs.stat(genPath))
        } catch {
        | _ => None
        }

        switch stat {
        | Some(s) if s.isDirectory() => {
          // Hygen convention: _templates/<generator>/<action>/<template>.ejs.t
          let templates = await loadGeneratorTemplates(~fs, ~path, genPath)

          // Fail-fast: if the manifest fails to parse or validate, skip this
          // generator entirely (with a visible warning) instead of silently
          // returning it with a malformed/missing manifest attached.
          switch await _loadManifest(~fs, ~path, ~yamlParser, genPath) {
          | Ok(maybeM) =>
            Some({
              name: entry,
              path: genPath,
              templates,
              manifest: ?maybeM,
            })
          | Error(reason) => {
              Console.warn("Skipping generator " ++ entry ++ ": " ++ reason)
              None
            }
          }
          }
        | _ => None
        }
      })

      let results = await Promise.all(genPromises)
      results->Array.filterMap(x => x)
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => ""
      }
      if String.startsWith(msg, "Parse error in ") {
        Console.warn(msg)
        []
      } else {
        // Silent — errors on non-generator dirs are expected
        []
      }
    }
  }
}

// Discover generator metadata without reading template bodies.
let discoverGenerators: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~yamlParser: Ports.yamlParser,
  ~searchPaths: array<string>=?,
  unit,
) => promise<array<generatorMeta>> = async (~fs, ~path, ~yamlParser, ~searchPaths=?, ()) => {
  let defaultPaths = ["_templates", "templates", "generators"]
  let paths = switch searchPaths {
  | Some(p) => p
  | None => defaultPaths
  }

  let discoveredPaths = await Promise.all(paths->Array.map(async baseDir => {
    let exists = await fs.fileExists(baseDir)
    if !exists {
      []
    } else {
      try {
        let entries = await fs.readdir(baseDir, ~options={withFileTypes: false})
        let metadata = await Promise.all(entries->Array.map(async entry => {
          let genPath = path.join(baseDir, entry)
          let stat = try {
            Some(await fs.stat(genPath))
          } catch {
          | _ => None
          }

          switch stat {
          | Some(s) if s.isDirectory() => {
              // Validate the manifest before inspecting actions or reading any templates.
              switch await _loadManifest(~fs, ~path, ~yamlParser, genPath) {
              | Error(reason) => {
                  Console.warn("Skipping generator " ++ entry ++ ": " ++ reason)
                  None
                }
              | Ok(manifest) => {
                  // Match full discovery's action-entry stat/isDirectory checks without reading files.
                  let actionEntries = try {
                    await fs.readdir(genPath, ~options={withFileTypes: false})
                  } catch {
                  | exn =>
                    let msg = _errorMessage(exn, "Failed to read directory " ++ genPath)
                    if !_isNotFound(msg) {
                      Console.warn("Skipping directory " ++ genPath ++ ": " ++ msg)
                    }
                    []
                  }
                  let actionChecks = await Promise.all(actionEntries->Array.map(async actionName => {
                    let actionPath = path.join(genPath, actionName)
                    try {
                      let actionStat = await fs.stat(actionPath)
                      actionStat.isDirectory()
                    } catch {
                    | _ => false
                    }
                  }))
                  let _hasActionDirectory = actionChecks->Array.some(isDirectory => isDirectory)
                  Some({name: entry, path: genPath, manifest})
                }
              }
            }
          | _ => None
          }
        }))
        metadata->Array.filterMap(x => x)
      } catch {
      | JsExn(obj) =>
        let msg = switch JsExn.message(obj) {
        | Some(m) => m
        | None => ""
        }
        if String.startsWith(msg, "Parse error in ") {
          Console.warn(msg)
          []
        } else {
          []
        }
      }
    }
  }))

  discoveredPaths->Array.reduce([], (acc, gens) => acc->Array.concat(gens))
}

let findByClassificationMeta: (array<generatorMeta>, string) => option<generatorMeta> = (
  generators,
  classification,
) => generators->Array.find(g => g.name == classification)

// Discover generators across standard search paths
let discover: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~yamlParser: Ports.yamlParser,
  ~searchPaths: array<string>=?,
  unit,
) => promise<array<generator>> = async (~fs, ~path, ~yamlParser, ~searchPaths=?, ()) => {
  let defaultPaths = ["_templates", "templates", "generators"]
  let paths = switch searchPaths {
  | Some(p) => p
  | None => defaultPaths
  }

  let allGenPromises = paths->Array.map(baseDir => discoverIn(~fs, ~path, ~yamlParser, baseDir))
  let allResults = await Promise.all(allGenPromises)

  // Flatten all generators from all paths
  let allGenerators = allResults->Array.reduce([], (acc, gens) => {
    acc->Array.concat(gens)
  })

  allGenerators
}

// Find a generator by classification/name
let findByClassification: (array<generator>, string) => option<generator> = (
  generators,
  classification,
) => {
  generators->Array.find(g => g.name == classification)
}
