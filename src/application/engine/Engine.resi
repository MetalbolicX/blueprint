// Engine.resi
open EngineResult

let run: (
  ~generator: Discovery.generator,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~outputDir: string,
  ~force: bool,
  ~config: Config.config=?,
  ~deps: Ports.deps,
) => promise<result<generateResult, Commit.phase2Error>>
