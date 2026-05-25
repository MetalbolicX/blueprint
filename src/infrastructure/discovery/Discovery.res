// Discovery — traverse _templates/ directory, find generators
// Follows Hygen's _templates/<generator>/<action>/ convention

open Template

type generator = {
  name: string, // directory name (e.g. "component")
  path: string, // absolute path to generator dir
  templates: array<template>, // .ejs.t files found
  manifest?: Manifest.manifest, // manifest.yaml if present
}

let _isTemplateFile: string => bool = filename => {
  String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl")
}

let isManifestFile: string => bool = filename => {
  filename == "manifest.yaml"
}

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
      | Error(_e) => None
      }
    }
  } catch {
  | JsExn(obj) =>
    let _msg = switch JsExn.message(obj) {
    | Some(m) => "Failed to load template " ++ sourcePath ++ ": " ++ m
    | None => "Failed to load template " ++ sourcePath
    }
    None
  }
}

// Load manifest.yaml from a generator directory if present
let _loadManifest: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<option<Manifest.manifest>> = async (
  ~fs,
  ~path,
  generatorPath,
) => {
  let manifestPath = path.join(generatorPath, "manifest.yaml")

  let exists = await fs.fileExists(manifestPath)
  if !exists {
    None
  } else {
    try {
      let content = await fs.readFile(manifestPath, ~options={encoding: "utf8"})
      switch Manifest.parse(content) {
      | Ok(m) => Some(m)
      | Error(_) => None
      }
    } catch {
    | _ => None
    }
  }
}

// Discover all generators under a base directory
let discoverIn: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<array<generator>> = async (
  ~fs,
  ~path,
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
          let actionEntries = try {
            await fs.readdir(genPath, ~options={withFileTypes: false})
          } catch {
          | JsExn(_) => []
          }

          let actionTmplPromises = actionEntries->Array.map(async actionName => {
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
              | JsExn(_) => []
              }

              let filePromises = files->Array.map(fname => {
                if _isTemplateFile(fname) {
                  let fpath = path.join(actionPath, fname)
                  _loadTemplate(~fs, ~path, fpath)
                } else {
                  Promise.resolve(None)
                }
              })

              let loaded = await Promise.all(filePromises)
              loaded->Array.filterMap(x => x)
            }
            | _ => []
            }
          })

          let allActionTemplates = await Promise.all(actionTmplPromises)
          let templates = allActionTemplates->Array.reduce([], (acc, t) =>
            acc->Array.concat(t)
          )
          let manifest = await _loadManifest(~fs, ~path, genPath)

          Some({
            name: entry,
            path: genPath,
            templates,
            manifest: ?manifest,
          })
        }
        | _ => None
        }
      })

      let results = await Promise.all(genPromises)
      results->Array.filterMap(x => x)
    } catch {
    | JsExn(obj) =>
      // Silent — errors on non-generator dirs are expected
      let _ = JsExn.message(obj)
      []
    }
  }
}

// Discover generators across standard search paths
let discover: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~searchPaths: array<string>=?,
  unit,
) => promise<array<generator>> = async (~fs, ~path, ~searchPaths=?, ()) => {
  let defaultPaths = ["_templates", "templates", "generators"]
  let paths = switch searchPaths {
  | Some(p) => p
  | None => defaultPaths
  }

  let allGenPromises = paths->Array.map(baseDir => discoverIn(~fs, ~path, baseDir))
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
