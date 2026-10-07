type generator = {
  name: string,
  path: string,
  templates: array<Template.template>,
  manifest?: Manifest.manifest,
}

type generatorMeta = {
  name: string,
  path: string,
  manifest: option<Manifest.manifest>,
}

let discoverIn: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, string) => promise<array<generator>>
let loadGeneratorTemplates: (~fs: Ports.fileSystem, ~path: Ports.path, string) => promise<array<Template.template>>
let discoverGenerators: (~fs: Ports.fileSystem, ~path: Ports.path, ~yamlParser: Ports.yamlParser, ~searchPaths: array<string>=?, unit) => promise<array<generatorMeta>>
let findByClassificationMeta: (array<generatorMeta>, string) => option<generatorMeta>
