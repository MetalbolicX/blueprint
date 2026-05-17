type generator = {
  name: string,
  path: string,
  templates: array<Template.template>,
  manifest?: Manifest.manifest,
}

let discover: (~searchPaths: array<string>=?, unit) => promise<array<generator>>
let findByClassification: (array<generator>, string) => option<generator>
