// Commands — aggregator re-exporting per-command modules under commands/
// Backwards-compatible run functions delegate to the individual command modules.
module InitGlobal = InitGlobal
module TemplateCopy = TemplateCopy
module TemplateList = TemplateList
module TemplateRemove = TemplateRemove
module Init = Init
module Generate = Generate

// Backwards-compatible run functions used by Router.res
let runInitGlobal: (~deps: Ports.deps) => promise<unit> = InitGlobal.runInitGlobal

let runTemplateCopy: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~force: bool,
) => promise<unit> = TemplateCopy.runTemplateCopy

let runTemplateList: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<unit> = TemplateList.runTemplateList

let runTemplateRemove: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
) => promise<unit> = TemplateRemove.runTemplateRemove

let runInit: (~deps: Ports.deps) => promise<unit> = Init.runInit

let runGenerate: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~classification: string,
  ~name: string,
  ~force: bool,
  ~outputDir: string,
  ~cliAttributes: dict<Context.attrValue>,
) => promise<unit> = Generate.runGenerate
