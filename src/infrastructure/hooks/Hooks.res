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
) => promise<result<hookResult, string>> = async (
  ~hook,
  ~cwd,
  ~timeout,
  ~hookType,
  ~shellEnv,
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
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, NodeJs.NodeProcess.env->Obj.magic)

  // Check for path restriction on any command that looks like a path
  let isPath = _isPath(hook.command)

  // Helper to build execFile options
  let execFileOpts: ChildProcess.execOptions = {
    cwd: cwd,
    env: safeEnv,
    encoding: "utf8",
  }

  // Use promisified exec to properly detect timeout
  // The callback style exec gives us (err, stdout, stderr) directly
  let execWithTimeout: (string, int) => promise<result<ChildProcess.execResult, string>> = async (_cmd, _timeoutMs) => {
    try {
      let result = await %raw("(async () => {
        const {exec} = await import('node:child_process');
        const {promisify} = await import('node:util');
        const execP = promisify(exec);
        return execP(cmd, {timeout: timeoutMs});
      })()")
      Ok(result)
    } catch {
    | JsExn(e) =>
      let msg = switch JsExn.message(e) {
      | Some(m) => m
      | None => "unknown error"
      }
      Error(msg)
    }
  }

  let result = if isPath {
    let resolvedPath = Path.resolve(cwd, hook.command)
    if !PathSecurity.isWithinTree(resolvedPath, cwd) {
      Error("Hook script outside project tree: " ++ hook.command)
    } else {
      switch hook.args {
      | Some(args) => Ok(await ChildProcess.execFile(hook.command, ~args, ~options=execFileOpts))
      | None => await execWithTimeout(hook.command, timeout)
      }
    }
  } else {
    switch hook.args {
    | Some(args) => Ok(await ChildProcess.execFile(hook.command, ~args, ~options=execFileOpts))
    | None => await execWithTimeout(hook.command, timeout)
    }
  }
  switch result {
  | Error(e) => Error(e)
  | Ok(r) =>
    let code = switch r.status {
    | Some(c) => c
    | None => 0
    }
    if code != 0 {
      Error("Hook exited with code " ++ Int.toString(code))
    } else {
      Ok({hookType, output: r.stdout, exitCode: code})
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
) => promise<result<unit, string>> = async (
  ~config,
  ~projectRoot,
  ~hookType,
  ~shellConfig,
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
  | Some(hook) => {
      let shellEnv = _buildShellEnv(shellConfig)
      let result = await executeHook(~hook, ~cwd=projectRoot, ~timeout, ~hookType, ~shellEnv)
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