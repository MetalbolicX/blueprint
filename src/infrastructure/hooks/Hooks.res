// Hooks — pre/post generate lifecycle hook execution
// Mirrors Go version's hooks/hooks.go

open Bindings
open EnvFilter

type hookType = PreGenerate | PostGenerate

type hookResult = {
  hookType: hookType,
  output: string,
  exitCode: int,
}

// Check if a command looks like a path (needs path restriction)
// Paths include: ./script.sh, ../script.sh, /etc/passwd, bin/echo
// Non-paths (allowed without restriction): echo, exit, ls, npm, etc.
let _isPath: string => bool = cmd => {
  Js.String.includes("/", cmd)
}

// Execute a single hook using structured hookCommand
let executeHook: (
  ~hook: Config.hookCommand,
  ~cwd: string,
  ~timeout: int,
  ~hookType: hookType,
  ~shellEnv: option<Config.shellEnv>,
  ~shell: Ports.shell,
  ~process: Ports.process,
) => promise<result<hookResult, string>> = async (
  ~hook,
  ~cwd,
  ~timeout,
  ~hookType,
  ~shellEnv,
  ~shell,
  ~process,
) => {
  // Build safe env for child process
  let buildEnvEntry: (string, string) => EnvFilter.shellEnvEntry = (k, v) => {
    {key: k, value: v}
  }
  let buildEnvFilterConfig: Config.shellEnv => EnvFilter.shellEnvConfig = s => {
    let entries: array<EnvFilter.shellEnvEntry> = s.vars->Dict.toArray->Array.map(((k, v)) => {
      buildEnvEntry(k, v)
    })
    {vars: entries}
  }
  // Handle null/undefined/None gracefully - all mean no shell env config
  let envFilterConfig: option<EnvFilter.shellEnvConfig> = switch shellEnv {
  | Some(s) => Some(buildEnvFilterConfig(s))
  | None => None
  }
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, process.env())

  // Check for path restriction on any command that looks like a path
  let isPath = _isPath(hook.command)

  // Helper to build execFile options
  let execFileOpts: ChildProcess.execOptions = {
    cwd: cwd,
    env: safeEnv,
    encoding: "utf8",
  }

  // Use shell port for proper timeout handling
  let execWithTimeout: (string, int) => promise<result<Ports.execResult, string>> = async (cmd, timeoutMs) => {
    try {
      let options: Ports.shellOptions = {timeout: timeoutMs}
      let result = await shell.execAsync(cmd, ~options)
      Ok(result)
    } catch {
    | JsExn(e) =>
      let msg = switch Js.Exn.message(e->Obj.magic) {
      | Some(m) => m
      | None => "unknown error"
      }
      Error(msg)
    }
  }

  // Check if hook command is empty - skip execution
  let isEmptyCommand = hook.command == ""

  let execResultToHookResult: Ports.execResult => hookResult = execResult => {
    let exitCode = switch execResult.status {
    | Some(c) => c
    | None => 0
    }
    {hookType, output: execResult.stdout, exitCode}
  }

  let result = if isEmptyCommand {
    Ok({hookType, output: "", exitCode: 0})
  } else if isPath {
    let resolvedPath = Path.resolve(cwd, hook.command)
    if !PathSecurity.isWithinTree(resolvedPath, cwd) {
      Error("Hook script outside project tree: " ++ hook.command)
    } else {
      switch hook.args {
      | Some(args) => {
    let r = await ChildProcess.execFileAsync(hook.command, ~args, ~options=execFileOpts)
          Ok(execResultToHookResult((r :> Ports.execResult)))
        }
      | None => {
          let r = await ChildProcess.execFileAsync(hook.command, ~options=execFileOpts)
          Ok(execResultToHookResult((r :> Ports.execResult)))
        }
      }
    }
  } else {
    switch hook.args {
    | Some(args) => {
        let r = await ChildProcess.execFileAsync(hook.command, ~args, ~options=execFileOpts)
        Ok(execResultToHookResult((r :> Ports.execResult)))
      }
    | None => {
        let r = await execWithTimeout(hook.command, timeout)
        switch r {
        | Ok(r2) => Ok(execResultToHookResult(r2))
        | Error(e) => Error(e)
        }
      }
    }
  }
  switch result {
  | Error(e) => Error(e)
  | Ok(r) =>
    if r.exitCode != 0 {
      Error("Hook exited with code " ++ Int.toString(r.exitCode))
    } else {
      Ok(r)
    }
  }
}

// Build shellEnv from shellConfig
let _buildShellEnv: option<Config.shellConfig> => option<Config.shellEnv> = shellConfig => {
  shellConfig->Option.flatMap(s => s.env)
}

// Run hooks for a given hook type
let run: (
  ~config: Config.config,
  ~projectRoot: string,
  ~hookType: hookType,
  ~shellConfig: option<Config.shellConfig>,
  ~shell: Ports.shell,
  ~process: Ports.process,
) => promise<result<unit, string>> = async (
  ~config,
  ~projectRoot,
  ~hookType,
  ~shellConfig,
  ~shell,
  ~process,
) => {
  let timeout = switch config.hooks {
  | Some(h) =>
    switch h.timeout {
    | Some(t) => t * 1000 // Convert seconds to ms
    | None => 5000
    }
  | None => 5000
  }

  let hookCmd: option<Config.hookCommand> = switch config.hooks {
  | Some(h) =>
    switch hookType {
    | PreGenerate => h.preGenerate
    | PostGenerate => h.postGenerate
    }
  | None => None
  }

  switch hookCmd {
  | None => Ok()
  | Some(hook) =>
    if hook.command == "" {
      Ok()
    } else {
      let shellEnv = _buildShellEnv(shellConfig)
      let result = await executeHook(~hook, ~cwd=projectRoot, ~timeout, ~hookType, ~shellEnv, ~shell, ~process)
      switch result {
      | Ok(_) => Ok()
      | Error(e) =>
        switch hookType {
        | PreGenerate => Error("pre_generate hook failed: " ++ e)
        | PostGenerate => Error("post_generate hook failed: " ++ e)
        }
      }
    }
  }
}