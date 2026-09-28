// Hooks — pre/post generate lifecycle hook execution
// Mirrors Go version's hooks/hooks.go



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

// Local duplicate: ShellExecutor's matching tokenizer is not exported.
let tokenizeCommand: string => option<array<string>> = %raw(`command => {
  if (/[&;|$()<>\x60"'\n]/.test(command)) return undefined;
  const tokens = command.trim().split(/\s+/).filter(Boolean);
  return tokens.length === 0 ? undefined : tokens;
}`)

// Execute a single hook using structured hookCommand
// scriptRoot: directory for path containment validation (defaults to cwd for backward compat)
// cwd: working directory for execution (required)
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
  let scriptRoot = actualScriptRoot
    let envFilterConfig = shellEnv->Option.map(ShellBuilder.buildEnvFilterConfig)
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, process.env())

  // Check for path restriction on any command that looks like a path
  let isPath = _isPath(hook.command)

  // Preserve the original 30s bound for path-based hooks.
  let execFileOpts: Ports.shellOptions = {
    cwd: cwd,
    env: safeEnv,
    encoding: "utf8",
    timeout: ExecPolicy.defaultTimeout,
  }
  // Non-path tokenized commands retain the hook-specific timeout.
  let tokenizedExecFileOpts: Ports.shellOptions = {
    env: safeEnv,
    encoding: "utf8",
    timeout: timeout,
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
    let resolvedPath = path.resolve(scriptRoot, hook.command)
    let isWithin = await PathSecurity.isWithinTree(resolvedPath, scriptRoot, path, fs)
    if !isWithin {
      Error("Hook script outside project tree: " ++ hook.command)
    } else {
      switch hook.args {
      | Some(args) => {
          try {
            let r = await shell.execFileAsync(hook.command, ~args, ~options=execFileOpts)
            Ok(execResultToHookResult(r))
          } catch {
          | JsExn(e) => Error(JsExn.message(e)->Option.getOr("unknown error"))
          }
        }
      | None => {
          // Use node as interpreter for .mjs/.js scripts to avoid requiring
          // OS-level execute permission on the script file. The shebang
          // (#!/usr/bin/env node) requires execute permission at the OS level;
          // invoking via "node <path>" works with only read permission.
          let needsNode = String.endsWith(resolvedPath, ".mjs") || String.endsWith(resolvedPath, ".js")
          try {
            if needsNode {
              let r = await shell.execFileAsync("node", ~args=[resolvedPath], ~options=execFileOpts)
              Ok(execResultToHookResult(r))
            } else {
              let r = await shell.execFileAsync(hook.command, ~options=execFileOpts)
              Ok(execResultToHookResult(r))
            }
          } catch {
          | JsExn(e) => Error(JsExn.message(e)->Option.getOr("unknown error"))
          }
        }
      }
    }
  } else {
    switch hook.args {
    | Some(args) => {
        try {
          let r = await shell.execFileAsync(hook.command, ~args, ~options=execFileOpts)
          Ok(execResultToHookResult(r))
        } catch {
        | JsExn(e) => Error(JsExn.message(e)->Option.getOr("unknown error"))
        }
      }
    | None => {
        switch tokenizeCommand(hook.command) {
        | None => Error("Hook " ++ hook.command ++ " must be a non-empty command without shell metacharacters; use a script path or the structured args field for complex commands")
        | Some(tokens) => {
            let command = tokens->Array.get(0)->Option.getOr("")
            let args = tokens->Array.slice(~start=1, ~end=tokens->Array.length)
            let allowed = switch toolsAllowlist {
            | Some(Some(tools)) if tools->Array.length > 0 => tools->Array.some(tool => tool == command)
            | _ => true
            }
            if !allowed {
              Error("Hook command not in tools allowlist: " ++ command)
            } else {
              try {
                let r = await shell.execFileAsync(command, ~args, ~options=tokenizedExecFileOpts)
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

// Build shellEnv from shellConfig
let _buildShellEnv: option<Config.shellConfig> => option<Config.shellEnv> = shellConfig => {
  shellConfig->Option.flatMap(s => s.env)
}

// Run hooks for a given hook type
// scriptRoot: directory for path containment validation (generator.path or projectRoot)
// cwd: working directory for execution (outputDir for generator hooks; projectRoot for config hooks)
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
  | None => Ok({hookType, output: "", exitCode: 0})
  | Some(hook) =>
    if hook.command == "" {
      Ok({hookType, output: "", exitCode: 0})
    } else {
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
    }
  }
}
