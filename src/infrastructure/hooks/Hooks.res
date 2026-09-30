// Hooks — pre/post generate lifecycle hook execution
// Mirrors Go version's hooks/hooks.go

type hookType = PreGenerate | PostGenerate

type hookResult = {
  hookType: hookType,
  output: string,
  exitCode: int,
}

let _isPath: string => bool = cmd => Js.String.includes("/", cmd)

// Match ShellExecutor's deliberately conservative tokenization.
let tokenizeCommand: string => option<array<string>> = %raw(`command => {
  if (/[&;|$()<>\x60"'\n]/.test(command)) return undefined;
  const tokens = command.trim().split(/\s+/).filter(Boolean);
  return tokens.length === 0 ? undefined : tokens;
}`)

let executeHook: (
  ~hook: Config.hookCommand,
  ~scriptRoot: string=?,
  ~cwd: string,
  ~timeout: int,
  ~hookType: hookType,
  ~shellEnv: option<Config.shellEnv>,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~toolsAllowlist: option<array<string>>=?,
) => promise<result<hookResult, string>> = async (
  ~hook,
  ~scriptRoot as actualScriptRoot=".",
  ~cwd,
  ~timeout,
  ~hookType,
  ~shellEnv,
  ~shell,
  ~process,
  ~path,
  ~fs,
  ~toolsAllowlist=?,
) => {
  let scriptRoot = if actualScriptRoot == "." { cwd } else { actualScriptRoot }
  let envFilterConfig = shellEnv->Option.map(ShellBuilder.buildEnvFilterConfig)
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, process.env())
  let execOptions: Ports.shellOptions = {
    cwd: cwd,
    env: safeEnv,
    encoding: "utf8",
    timeout: timeout,
  }

  let execResultToHookResult: Ports.execResult => hookResult = execResult => {
    let exitCode = switch execResult.status {
    | Some(c) => c
    | None => 0
    }
    {hookType, output: execResult.stdout, exitCode}
  }

  let result = if hook.command == "" {
    Ok({hookType, output: "", exitCode: 0})
  } else {
    let explicitArgs = hook.args
    let tokenized = switch explicitArgs {
    | Some(_) => None
    | None => tokenizeCommand(hook.command)
    }
    switch (explicitArgs, tokenized) {
    | (None, None) => Error("Hook " ++ hook.command ++ " must be a non-empty command without shell metacharacters; use a script path or the structured args field for complex commands")
    | _ => {
        let rawExecutable = switch explicitArgs {
        | Some(_) => hook.command
        | None => tokenized->Option.getOr([])->Array.get(0)->Option.getOr("")
        }
        let isPath = _isPath(rawExecutable)
        // Resolve path executables once; validation and execution share this value.
        let resolvedExecutable = if isPath {
          path.resolve(scriptRoot, rawExecutable)
        } else {
          rawExecutable
        }
        let allowed = switch toolsAllowlist {
        | Some(Some(tools)) => tools->Array.some(tool => tool == rawExecutable || tool == resolvedExecutable)
        | _ => true
        }
        if !allowed {
          Error("Hook command not in tools allowlist: " ++ rawExecutable)
        } else {
          let pathIsSafe = if isPath {
            await PathSecurity.isWithinTree(resolvedExecutable, scriptRoot, path, fs)
          } else {
            true
          }
          if !pathIsSafe {
            Error("Hook script outside project tree: " ++ rawExecutable)
          } else {
            let pathExists = if isPath {
              await fs.fileExists(resolvedExecutable)
            } else {
              true
            }
            if !pathExists {
              Error("Hook script not found: " ++ resolvedExecutable)
            } else {
              let args = switch explicitArgs {
              | Some(args) => args
              | None => tokenized->Option.getOr([])->Array.slice(~start=1)
              }
              let needsNode = isPath && Option.isNone(explicitArgs) && (String.endsWith(resolvedExecutable, ".mjs") || String.endsWith(resolvedExecutable, ".js"))
              let executable = if needsNode { "node" } else { resolvedExecutable }
              let execArgs = if needsNode { Array.concat([resolvedExecutable], args) } else { args }
              try {
                let r = await shell.execFileAsync(executable, ~args=execArgs, ~options=execOptions)
                Ok(execResultToHookResult(r))
              } catch {
              | JsExn(e) => Error(JsExn.message(e)->Option.getOr("unknown error"))
              }
            }
          }
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

let _buildShellEnv: option<Config.shellConfig> => option<Config.shellEnv> = shellConfig => {
  shellConfig->Option.flatMap(s => s.env)
}

let run: (
  ~config: Config.config,
  ~projectRoot: string,
  ~hookType: hookType,
  ~shellConfig: option<Config.shellConfig>,
  ~shell: Ports.shell,
  ~process: Ports.process,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~scriptRoot: string=?,
  ~cwd: string=?,
  ~toolsAllowlist: option<array<string>>=?,
) => promise<result<hookResult, string>> = async (
  ~config,
  ~projectRoot,
  ~hookType,
  ~shellConfig,
  ~shell,
  ~process,
  ~path,
  ~fs,
  ~scriptRoot as actualScriptRoot=projectRoot,
  ~cwd as actualCwd=projectRoot,
  ~toolsAllowlist=?,
) => {
  let scriptRoot = actualScriptRoot
  let cwd = actualCwd
  let timeout = switch config.hooks {
  | Some(h) => {
      let seconds = h.timeout->Option.getOr(5)
      (if seconds > 600 { 600 } else { seconds }) * 1000
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
  | None => Ok({hookType, output: "", exitCode: 0})
  | Some(hook) if hook.command == "" => Ok({hookType, output: "", exitCode: 0})
  | Some(hook) =>
    switch shellConfig {
    | Some(cfg) if !cfg.enabled =>
      let hookName = switch hookType {
      | PreGenerate => "pre_generate"
      | PostGenerate => "post_generate"
      }
      Error(hookName ++ " hook refused: shell execution disabled")
    | _ => {
        try {
          // A declared execution cwd must exist for child_process.execFile.
          let _ = await fs.mkdir(cwd, ~options={recursive: true})
          let shellEnv = _buildShellEnv(shellConfig)
          let result = await executeHook(~hook, ~scriptRoot, ~cwd, ~timeout, ~hookType, ~shellEnv, ~shell, ~process, ~path, ~fs, ~toolsAllowlist=?toolsAllowlist)
          switch result {
          | Ok(r) => Ok(r)
          | Error(e) =>
            switch hookType {
            | PreGenerate => Error("pre_generate hook failed: " ++ e)
            | PostGenerate => Error("post_generate hook failed: " ++ e)
            }
          }
        } catch {
        | JsExn(e) => Error("Hook working directory unavailable: " ++ JsExn.message(e)->Option.getOr("unknown error"))
        }
      }
    }
  }
}
