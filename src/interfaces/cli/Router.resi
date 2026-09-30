let extractAttributes: (~args: array<string>) => dict<Context.attrValue>

let findPackageJson: (
  string,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~depth: int=?,
) => promise<option<string>>

let route: (~deps: Ports.deps, ~args: array<string>) => promise<unit>
