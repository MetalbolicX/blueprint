// Discovery — traverse _templates/ directory, find generators
// Follows Hygen's _templates/<generator>/<action>/ convention

open Template
open Bindings

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
let _loadTemplate: string => promise<option<template>> = async sourcePath => {
  try {
    let content = await Bindings.Fs.readFile(sourcePath, ~options={encoding: "utf8"})
    let filename = Path.basename(sourcePath)

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
let _loadManifest: string => promise<option<Manifest.manifest>> = async generatorPath => {
  let manifestPath = Path.join(generatorPath, "manifest.yaml")

  let exists = await Bindings.Fs.fileExists(manifestPath)
  if !exists {
    None
  } else {
    try {
      let content = await Bindings.Fs.readFile(manifestPath, ~options={encoding: "utf8"})
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
let discoverIn: string => promise<array<generator>> = async baseDir => {
  let exists = await Bindings.Fs.fileExists(baseDir)
  if !exists {
    []
  } else {
    try {
      let entries = await Bindings.Fs.readdir(baseDir, ~options={withFileTypes: false})

      let genPromises = entries->Array.map(async entry => {
        let genPath = Bindings.Path.join(baseDir, entry)
        let stat = try {
          Some(await Bindings.Fs.stat(genPath))
        } catch {
        | _ => None
        }

        switch stat {
        | Some(s) if s.isDirectory() => {
          let templateFiles = try {
            await Bindings.Fs.readdir(genPath, ~options={withFileTypes: false})
          } catch {
          | JsExn(obj) =>
            // Silent — errors on non-template files are expected
            let _msg = switch JsExn.message(obj) {
            | Some(m) => m
            | None => "unknown"
            }
            []
          }

          let tmplPromises = templateFiles->Array.map(async fname => {
            if _isTemplateFile(fname) {
              let fpath = Bindings.Path.join(genPath, fname)
              await _loadTemplate(fpath)
            } else {
              None
            }
          })

          let loaded = await Promise.all(tmplPromises)
          let templates = loaded->Array.filterMap(x => x)
          let manifest = await _loadManifest(genPath)

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
let discover: (~searchPaths: array<string>=?, unit) => promise<array<generator>> = async (
  ~searchPaths=?,
  (),
) => {
  let defaultPaths = ["_templates", "templates", "generators"]
  let paths = switch searchPaths {
  | Some(p) => p
  | None => defaultPaths
  }

  let allGenPromises = paths->Array.map(baseDir => discoverIn(baseDir))
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
