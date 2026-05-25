let buildGenerateSearchPaths: (
  ~projectPaths: array<string>,
  ~registry: array<Config.templateSource>,
  ~globalTemplates: array<string>,
) => array<string>

let copyTemplateToRegistry: (
  ~name: string,
  ~sourcePath: string,
  ~registryRoot: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
  ~force: bool,
  ~confirmOverwrite: string => promise<bool>,
) => promise<result<Config.globalConfig, string>>

let removeTemplateFromRegistry: (
  ~name: string,
  ~configPath: string,
  ~globalConfig: Config.globalConfig,
) => promise<result<Config.globalConfig, string>>

let main: unit => promise<unit>
