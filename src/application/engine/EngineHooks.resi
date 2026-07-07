// EngineHooks.resi
open EngineResult

let runPreHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, string>>

let runPostHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~result: generateResult,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<generateResult, string>>
