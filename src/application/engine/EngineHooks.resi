// EngineHooks.resi
open EngineResult

let runPreHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~hooks: Ports.hooks,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~scriptRoot: string=?,
  ~cwd: string=?,
  ~preHook: option<Config.hookCommand>=?,
) => promise<result<Ports.hookResult, string>>

let runPostHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~result: generateResult,
  ~hooks: Ports.hooks,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~scriptRoot: string=?,
  ~cwd: string=?,
  ~postHook: option<Config.hookCommand>=?,
) => promise<result<generateResult, string>>
