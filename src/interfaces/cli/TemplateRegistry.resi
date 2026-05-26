let copyTemplateToRegistry: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~sourcePath: string,
  ~registryRoot: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
  ~force: bool,
  ~confirmOverwrite: string => promise<bool>,
) => promise<result<Config.globalConfig, string>>

let removeTemplateFromRegistry: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~name: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
) => promise<result<Config.globalConfig, string>>
