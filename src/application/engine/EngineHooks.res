// EngineHooks.res

open EngineResult

let runPreHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, string>> = async (~config, ~projectRoot, ~shell, ~process, ~path, ~fs) => {
  switch config {
  | None => Ok()
  | Some(c) =>
    let shellConfig = c.shell
    await Hooks.run(~config=c, ~projectRoot, ~hookType=Hooks.PreGenerate, ~shellConfig, ~shell, ~process, ~path, ~fs)
  }
}

let runPostHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~result: generateResult,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<generateResult, string>> = async (~config, ~projectRoot, ~result, ~shell, ~process, ~path, ~fs) => {
  switch config {
  | None => Ok(result)
  | Some(c) =>
    let shellConfig = c.shell
    let hookResult = await Hooks.run(~config=c, ~projectRoot, ~hookType=Hooks.PostGenerate, ~shellConfig, ~shell, ~process, ~path, ~fs)
    switch hookResult {
    | Error(e) => Error(e)
    | Ok() => Ok(result)
    }
  }
}
