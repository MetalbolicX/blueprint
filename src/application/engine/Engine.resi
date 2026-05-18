type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
}

let run: (
  ~generator: Discovery.generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
) => promise<result<generateResult, string>>

let runWithConfig: (
  ~generator: Discovery.generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~force: bool,
) => promise<result<generateResult, string>>
