// Engine - Facade for the template generation engine

let run = (
  ~generator,
  ~name,
  ~cliAttributes,
  ~outputDir,
  ~force,
  ~config=?,
  ~projectRoot=?,
  ~deps: Ports.deps,
) =>
  EngineOrchestrator.run(
    ~generator,
    ~name,
    ~cliAttributes,
    ~outputDir,
    ~force,
    ~config=?config,
    ~projectRoot=projectRoot->Option.getOr(deps.process.cwd()),
    ~deps,
  )
