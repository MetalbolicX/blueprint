// EngineHooks.res

open EngineResult

// scriptRoot: directory for path containment validation (generator.path or projectRoot)
// cwd: working directory for execution (outputDir for generator hooks; projectRoot for config hooks)
// preHook/postHook: optional explicit hook command override; if provided, wins over config hook
let runPreHook: (
  ~config: option<Config.config>,
  ~projectRoot: string,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~scriptRoot: string=?,
  ~cwd: string=?,
  ~preHook: option<Config.hookCommand>=?,
) => promise<result<Hooks.hookResult, string>> = async (
  ~config,
  ~projectRoot,
  ~shell,
  ~process,
  ~path,
  ~fs,
  ~scriptRoot as actualScriptRoot=projectRoot,
  ~cwd as actualCwd=projectRoot,
  ~preHook as actualPreHook=None,
) => {
  let scriptRoot = actualScriptRoot
  let cwd = actualCwd
  // Resolve effective hook: explicit preHook wins over config hook
  let effectiveHook: option<Config.hookCommand> = switch actualPreHook {
  | Some(h) => Some(h)
  | None =>
    switch config {
    | Some(c) => c.hooks->Option.flatMap(h => h.preGenerate)
    | None => None
    }
  }
  switch effectiveHook {
  | None => Ok({hookType: Hooks.PreGenerate, output: "", exitCode: 0})
  | Some(hook) =>
     let shellConfig = config->Option.flatMap(c => c.shell)
     let toolsAllowlist = shellConfig->Option.flatMap(s => s.tools)->Option.map(tools => tools->Array.map(tool => tool.command))
    let timeout = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.timeout)
    // Build hooks config with explicit preGenerate
    let hooksCfg: Config.hooksConfig = {
      preGenerate: hook,
      timeout: ?timeout,
    }
    let hookConfig: Config.config = {
      hooks: hooksCfg,
      shell: ?shellConfig,
    }
     await Hooks.run(~config=hookConfig, ~projectRoot, ~hookType=Hooks.PreGenerate, ~shellConfig, ~shell, ~process, ~path, ~fs, ~scriptRoot, ~cwd, ~toolsAllowlist)
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
  ~scriptRoot: string=?,
  ~cwd: string=?,
  ~postHook: option<Config.hookCommand>=?,
) => promise<result<generateResult, string>> = async (
  ~config,
  ~projectRoot,
  ~result,
  ~shell,
  ~process,
  ~path,
  ~fs,
  ~scriptRoot as actualScriptRoot=projectRoot,
  ~cwd as actualCwd=projectRoot,
  ~postHook as actualPostHook=None,
) => {
  let scriptRoot = actualScriptRoot
  let cwd = actualCwd
  // Resolve effective hook: explicit postHook wins over config hook
  let effectiveHook: option<Config.hookCommand> = switch actualPostHook {
  | Some(h) => Some(h)
  | None =>
    switch config {
    | Some(c) => c.hooks->Option.flatMap(h => h.postGenerate)
    | None => None
    }
  }
  switch effectiveHook {
  | None => Ok(result)
  | Some(hook) =>
     let shellConfig = config->Option.flatMap(c => c.shell)
     let toolsAllowlist = shellConfig->Option.flatMap(s => s.tools)->Option.map(tools => tools->Array.map(tool => tool.command))
    let timeout = config->Option.flatMap(c => c.hooks)->Option.flatMap(h => h.timeout)
    let hooksCfg: Config.hooksConfig = {
      postGenerate: hook,
      timeout: ?timeout,
    }
    let hookConfig: Config.config = {
      hooks: hooksCfg,
      shell: ?shellConfig,
    }
     let hookResult = await Hooks.run(~config=hookConfig, ~projectRoot, ~hookType=Hooks.PostGenerate, ~shellConfig, ~shell, ~process, ~path, ~fs, ~scriptRoot, ~cwd, ~toolsAllowlist)
    switch hookResult {
    | Error(e) => Error(e)
    | Ok(_) => Ok(result)
    }
  }
}
