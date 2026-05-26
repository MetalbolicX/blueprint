let runInit: (~deps: Ports.deps) => promise<unit>

let runInitGlobal: (~deps: Ports.deps) => promise<unit>

let runGenerate: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~deps: Ports.deps,
  ~classification: string,
  ~name: string,
  ~force: bool,
  ~outputDir: string,
  ~cliAttributes: dict<Context.attrValue>,
) => promise<unit>

let runTemplateCopy: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~force: bool,
) => promise<unit>

let runTemplateList: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<unit>

let runTemplateRemove: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
) => promise<unit>
