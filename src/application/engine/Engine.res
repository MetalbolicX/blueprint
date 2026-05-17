// Engine — temporary compile-safe orchestrator while migration continues.

open Discovery

type generateResult = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  classification: string,
}

let run: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~outputDir: string,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name as _name,
  ~cliAttributes as _cliAttributes,
  ~outputDir as _outputDir,
  ~force as _force,
) => {
  Ok({
    filesCreated: 0,
    filesInjected: 0,
    commandsExecuted: 0,
    classification: generator.name,
  })
}

let runWithConfig: (
  ~generator: generator,
  ~name: string,
  ~cliAttributes: dict<string>,
  ~force: bool,
) => promise<result<generateResult, string>> = async (
  ~generator,
  ~name,
  ~cliAttributes,
  ~force,
) => {
  await run(
    ~generator,
    ~name,
    ~cliAttributes,
    ~outputDir=Config.defaultOutputDir,
    ~force,
  )
}
