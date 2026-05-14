// Discovery — traverse _templates/ directory, find generators
// Follows Hygen's _templates/<generator>/<action>/ convention

open Templates

type generator = {
  name: string,                 // directory name (e.g. "component")
  path: string,                 // absolute path to generator dir
  templates: array<template>,    // .ejs.t files found
  manifest: option<Manifest.manifest>,  // manifest.yaml if present
}

let isTemplateFile: string => bool = filename => {
  Js.String.endsWith(filename, ".ejs.t") || Js.String.endsWith(filename, ".tmpl")
}

let isManifestFile: string => bool = filename => {
  filename == "manifest.yaml"
}

// Load and parse a single template file
let loadTemplate: string => promise<result<template, string>> = async sourcePath => {
  try {
    let content = await Bindings.Fs.readFile(sourcePath, ~options={encoding: "utf8"})
    let filename = Node.Path.basename(sourcePath)

    // Skip manifest files
    if isManifestFile(filename) {
      Error("Skipping manifest file")
    } else {
      switch Templates.Frontmatter.parse(content) {
      | Ok(parsed) => Ok({
          sourcePath: sourcePath,
          directives: parsed.directives,
          body: parsed.body,
        })
      | Error(e) => Error("Failed to parse frontmatter in " ++ sourcePath ++ ": " ++ e)
      }
    }
  } catch {
  | Js.Exn.Error(obj) =>
    let msg = switch Js.Exn.message(obj) {
    | Some(m) => "Failed to load template " ++ sourcePath ++ ": " ++ m
    | None => "Failed to load template " ++ sourcePath
    }
    Error(msg)
  }
}

// Load manifest.yaml from a generator directory if present
let loadManifest: string => promise<option<Manifest.manifest>> = async generatorPath => {
  let manifestPath = Node.Path.join(generatorPath, "manifest.yaml")

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
  let generators = Js.Array.empty()

  let exists = await Bindings.Fs.fileExists(baseDir)
  if !exists {
    []
  } else {
    try {
      // Read all entries in baseDir (non-recursive for top-level generators)
      let entries = await Bindings.Fs.readdir(baseDir, ~options={withFileTypes: false})

      // For each entry, check if it's a directory with templates
      entries->Js.Array.forEach(async entryName => {
        let entryPath = Node.Path.join(baseDir, entryName)

        let stat = await Bindings.Fs.stat(entryPath)
        if stat.isDirectory() {
          // Check if this directory has any .ejs.t files
          let templateFiles = await Bindings.Fs.readdir(entryPath, ~options={withFileTypes: false})
          let ejsFiles = templateFiles->Js.Array.filter(isTemplateFile)

          if Js.Array.length(ejsFiles) > 0 {
            // Load all templates
            let templates = ejsFiles->Js.Array.map(async filename => {
              let sourcePath = Node.Path.join(entryPath, filename)
              loadTemplate(sourcePath)
            })->Promise.all->Js.Array.filterMap(x => {
              switch x {
              | Ok(t) => Some(t)
              | Error(_) => None
              }
            })

            // Load manifest
            let manifest = await loadManifest(entryPath)

            let gen = {
              name: entryName,
              path: entryPath,
              templates: templates,
              manifest: manifest,
            }
            Js.Array.push(gen, generators)
          }
        }
      })

      generators
    } catch {
    | _ => []
    }
  }
}

// Discover generators across standard search paths
let discover: (~searchPaths: array<string>=?, unit) => promise<array<generator>> = async (~searchPaths=?, ()) => {
  let defaultPaths = ["_templates", "templates", "generators"]
  let paths = switch searchPaths {
  | Some(p) => p
  | None => defaultPaths
  }

  let allGenerators = Js.Array.empty()

  paths->Js.Array.forEach(async baseDir => {
    let discovered = await discoverIn(baseDir)
    discovered->Js.Array.forEach(g => Js.Array.push(g, allGenerators))
  })

  allGenerators
}

// Find a generator by classification/name
let findByClassification: (array<generator>, string) => option<generator> = (generators, classification) => {
  generators->Js.Array.find(g => g.name == classification)
}