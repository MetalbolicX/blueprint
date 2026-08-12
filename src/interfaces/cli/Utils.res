let globalTemplateRegistryRoot: (~deps: Ports.deps) => string = (~deps) => {
  let homeDir = deps.process.homedir()
  deps.path.join(deps.path.join(deps.path.join(homeDir, ".config"), "blueprint"), "templates")
}

let globalConfigPath: (~deps: Ports.deps) => string = (~deps) => {
  let homeDir = deps.process.homedir()
  deps.path.join(deps.path.join(deps.path.join(homeDir, ".config"), "blueprint"), "config.yaml")
}

let buildGenerateSearchPaths: (
  ~deps: Ports.deps,
  ~projectPaths: array<string>,
  ~registry: array<Config.templateSource>,
  ~globalTemplates: array<string>,
) => array<string> = (~deps: Ports.deps, ~projectPaths, ~registry, ~globalTemplates) => {
  let registryPaths = registry
  ->Array.map(src => deps.path.dirname(src.path))
  ->Array.reduce([], (acc, path) =>
    if acc->Array.includes(path) {
      acc
    } else {
      acc->Array.concat([path])
    }
  )
  let globalRoot = globalTemplateRegistryRoot(~deps)
  let base = projectPaths->Array.concat(registryPaths)->Array.concat(globalTemplates)
  if base->Array.includes(globalRoot) {
    base
  } else {
    base->Array.concat([globalRoot])
  }
}
