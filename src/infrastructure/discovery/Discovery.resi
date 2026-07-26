type generator = {
  name: string,
  path: string,
  templates: array<Template.template>,
  manifest?: Manifest.manifest,
}

let discoverIn: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, string) => promise<array<generator>>
let discover: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, ~searchPaths: array<string>=?, unit) => promise<array<generator>>
let findByClassification: (array<generator>, string) => option<generator>
