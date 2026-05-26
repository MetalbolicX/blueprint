let globalTemplateRegistryRoot: (~deps: Ports.deps) => string

let globalConfigPath: (~deps: Ports.deps) => string

let buildGenerateSearchPaths: (
  ~deps: Ports.deps,
  ~projectPaths: array<string>,
  ~registry: array<Config.templateSource>,
  ~globalTemplates: array<string>,
) => array<string>
