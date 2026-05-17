// Discovery — traverse _templates/ directory, find generators
// Follows Hygen's _templates/<generator>/<action>/ convention

open Template

type generator = {
  name: string, // directory name (e.g. "component")
  path: string, // absolute path to generator dir
  templates: array<template>, // .ejs.t files found
  manifest: option<Manifest.manifest>, // manifest.yaml if present
}

let _isTemplateFile: string => bool = filename => {
  String.endsWith(filename, ".ejs.t") || String.endsWith(filename, ".tmpl")
}

let isManifestFile: string => bool = filename => {
  filename == "manifest.yaml"
}

// Load and parse a single template file
let _loadTemplate: string => promise<result<template, string>> = async sourcePath => {
  try {
    let content = await Bindings.Fs.readFile(sourcePath, ~options={encoding: "utf8"})
    let filename = Path.basename(sourcePath)

    // Skip manifest files
    if isManifestFile(filename) {
      Error("Skipping manifest file")
    } else {
      switch Frontmatter.parse(content) {
      | Ok(parsed) =>
        Ok({
          sourcePath,
          directives: parsed.directives,
          body: parsed.body,
        })
      | Error(e) => Error("Failed to parse frontmatter in " ++ sourcePath ++ ": " ++ e)
      }
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => "Failed to load template " ++ sourcePath ++ ": " ++ m
    | None => "Failed to load template " ++ sourcePath
    }
    Error(msg)
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
let discoverIn: string => promise<array<generator>> = async _baseDir => {
  []
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
