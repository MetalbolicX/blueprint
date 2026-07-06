type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
  shellErrors?: array<string>,
}

let cleanupOrphans: (
  ~outputDir: string,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~tmpRoot: string=?,
) => promise<unit>

let registerSignalHandlers: (
  ~process: Ports.process,
  ~stagingDirRef: ref<option<string>>,
  ~fs: Ports.fileSystem,
) => unit

let run: (
  ~generator: Discovery.generator,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, string>>

