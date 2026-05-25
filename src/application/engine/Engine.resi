type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
  shellErrors?: array<string>,
}

let run: (
  ~generator: Discovery.generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, string>>

let runWithConfig: (
  ~generator: Discovery.generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~force: bool,
  ~deps: Ports.deps,
) => promise<result<generateResult, string>>
