type generator = {
  name: string,
  path: string,
  templates: array<Template.template>,
  manifest?: Manifest.manifest,
}

let discoverIn: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<array<generator>>
let discover: (~fs: Ports.fileSystem, ~path: Ports.path, ~searchPaths: array<string>=?, unit) => promise<array<generator>>
let findByClassification: (array<generator>, string) => option<generator>
