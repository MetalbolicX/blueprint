// ShellExecutor: Phase2 shell-command execution (Fetch download, Tool call, InlineCommand, Script).
// Owns fetch temp-file cleanup and the safe-env filter builder.
// No imports of other phase sub-modules — sits below Phase2 in the dependency arrow.

open Template

let cleanupFetchTmpFiles: (array<string>, ~fs: Ports.fileSystem) => promise<unit> = (tmpFiles, ~fs) => {
  tmpFiles
  ->Array.reduce(Promise.resolve(), (acc, tmpPath) => {
    acc->Promise.then(_ => {
      fs.rm(tmpPath, ~options={recursive: false})->Promise.catch(_ => Promise.resolve())
    })
  })
}

// Shared helper: runs a shell tool (execFileAsync or execAsync) with consistent
// options building, killed check, status check, and error mapping.
let execToolAsync = (
  ~run: (~options: Ports.shellOptions) => promise<Ports.execResult>,
  ~cwd,
  ~safeEnv,
  ~timeout,
  ~name,
  ~countRef,
) => {
  let opts: Ports.shellOptions = {
    cwd: cwd,
    env: safeEnv,
    encoding: "utf8",
    timeout: timeout,
  }
  run(~options=opts)->Promise.then(result => {
    if result.killed {
      Promise.resolve(Error("Tool '" ++ name ++ "' timed out after " ++ Int.toString(timeout) ++ "ms"))
    } else {
      switch result.status {
      | Some(0) => {
          countRef.contents = countRef.contents + 1
          Promise.resolve(Ok())
        }
      | status => Promise.resolve(Error("Tool '" ++ name ++ "' exited with code: " ++ Int.toString(status->Option.getOr(-1))))
      }
    }
  })->Promise.catch(e => {
    let msg = Errors.extractErrorMessage(e)
    Promise.resolve(Error("Tool '" ++ name ++ "' execution failed: " ++ msg))
  })
}

// Handler: Fetch — downloads URL content and writes to staging with hashed filename.
// Tracks the staging path in tmpFiles for cleanup and increments count on success.
let executeFetch = (
  ~url: string,
  ~stagingDir: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~tmpFiles: array<string>,
  ~countRef: ref<int>,
) => {
  Fetcher.fetch(url)->Promise.then(result => {
    switch result {
    | Ok(content) => {
        let fetchFileName = {
          let hashVal = url->String.split("")->Array.reduce(0, (acc, c) => {
            let code = switch String.charCodeAt(c, 0) {
            | Some(n) => n
            | None => 0
            }
            Math.Int.imul(acc, 31) + code
          })
          let hash = hashVal < 0 ? Int.toString(-hashVal) : Int.toString(hashVal)
          "fetch-" ++ hash ++ ".tmp"
        }
        let fetchPath = path.join(stagingDir, fetchFileName)
        fs.writeFile(fetchPath, content)->Promise.then(_ => {
          let _ = tmpFiles->Array.push(fetchPath)
          countRef.contents = countRef.contents + 1
          Promise.resolve(Ok())
        })->Promise.catch(e => {
          let msg = Errors.extractErrorMessage(e)
          Promise.resolve(Error("Failed to write fetched content: " ++ url ++ " — " ++ msg))
        })
      }
    | Error(msg) => {
        Promise.resolve(Error("Fetch failed: " ++ msg))
      }
    }
  })
}

// Handler: ToolCall — routes through ExecPolicy then execToolAsync.
// Increments count internally via countRef.
let executeToolCall = (
  ~name: string,
  ~toolDef: Config.shellTool,
  ~cwd: string,
  ~safeEnv: dict<string>,
  ~shellConfig: option<Config.shellConfig>,
  ~shell: Ports.shell,
  ~countRef: ref<int>,
) => {
  let toolsAllowlist: array<string> = shellConfig
    ->Option.flatMap(cfg => cfg.tools)
    ->Option.getOr([])
    ->Array.map(tool => tool.command)
  switch ExecPolicy.decide(~command=toolDef.command, ~args=toolDef.args, ~allowlist=toolsAllowlist) {
  | Reject(reason) => Promise.resolve(Error(reason))
  | ExecFile(command, args) => execToolAsync(
      ~run=(~options) => shell.execFileAsync(command, ~args, ~options),
      ~cwd,
      ~safeEnv,
      ~timeout=ExecPolicy.defaultTimeout,
      ~name,
      ~countRef,
    )
  | ShellExact(command) => execToolAsync(
      ~run=(~options) => shell.execAsync(command, ~options),
      ~cwd,
      ~safeEnv,
      ~timeout=ExecPolicy.defaultTimeout,
      ~name,
      ~countRef,
    )
  }
}

// Handler: InlineCommand — validates shell enabled, allowlist, and path security,
// then executes via execShellCommand. Increments count on success.
let executeInlineCommand = (
  ~command: string,
  ~cwd: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~shellConfig: option<Config.shellConfig>,
  ~shell: Ports.shell,
  ~countRef: ref<int>,
) => {
  let shellEnabled = switch shellConfig {
  | Some(cfg) => cfg.enabled
  | None => false
  }
  if !shellEnabled {
    Promise.resolve(Error("Shell execution disabled"))
  } else {
    let baseCmd = command->String.split(" ")->Array.get(0)->Option.getOr(command)
    let isAllowed = switch shellConfig {
    | Some(cfg) =>
      switch cfg.tools {
      | Some(tools) => tools->Array.some(tool => tool.command == baseCmd)
      | None => false
      }
    | None => false
    }
    if !isAllowed {
      Promise.resolve(Error("Command not in tools allowlist: " ++ command))
    } else {
      let resolvedCmd = path.resolve(cwd, baseCmd)
      PathSecurity.isWithinTree(resolvedCmd, cwd, path, fs)->Promise.then(isWithin => {
        if !isWithin {
          Promise.resolve(Error("Command path outside project tree: " ++ baseCmd))
        } else {
          shell.execShellCommand(~command, ~cwd, ~timeout=Some(ExecPolicy.defaultTimeout))->Promise.then(result => {
            switch result {
              | Ok(_) => {
                  countRef.contents = countRef.contents + 1
                  Promise.resolve(Ok())
                }
              | Error(e) => {
                  Promise.resolve(Error("Shell command failed: " ++ e))
                }
              }
          })
        }
      })
    }
  }
}

// Handler: ScriptFile — validates path security and file existence,
// then executes via execFileAsync. Increments count on success.
let executeScriptFile = (
  ~cmdPath: string,
  ~cwd: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~safeEnv: dict<string>,
  ~shell: Ports.shell,
  ~countRef: ref<int>,
) => {
  let resolvedPath = path.resolve(cwd, cmdPath)
  PathSecurity.isWithinTree(resolvedPath, cwd, path, fs)->Promise.then(isWithin => {
    if !isWithin {
      Promise.resolve(Error("Script path outside project tree: " ++ cmdPath))
    } else {
      fs.fileExists(resolvedPath)->Promise.then(exists => {
        if !exists {
          Promise.resolve(Error("Script file not found: " ++ cmdPath))
        } else {
          let execFileOpts: Ports.shellOptions = {
            cwd: cwd,
            env: safeEnv,
            encoding: "utf8",
            timeout: ExecPolicy.defaultTimeout,
          }
          shell.execFileAsync(resolvedPath, ~options=execFileOpts)->Promise.then(result => {
            if result.killed {
              Promise.resolve(Error("Script timed out after " ++ Int.toString(ExecPolicy.defaultTimeout) ++ "ms: " ++ cmdPath))
            } else {
              switch result.status {
              | Some(0) => {
                  countRef.contents = countRef.contents + 1
                  Promise.resolve(Ok())
                }
              | status => {
                  Promise.resolve(Error("Script exited with code " ++ Int.toString(status->Option.getOr(-1)) ++ ": " ++ cmdPath))
                }
              }
            }
          })->Promise.catch(e => {
            let msg = Errors.extractErrorMessage(e)
            Promise.resolve(Error("Script execution failed: " ++ msg ++ " (" ++ cmdPath ++ ")"))
          })
        }
      })
    }
  })
}

// Execute all queued shell commands
let executeShellCommands: (
  ~commands: array<shellCommand>,
  ~cwd: string,
  ~stagingDir: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
  ) => promise<result<int, string>> = (
  ~commands,
  ~cwd,
  ~stagingDir,
  ~shellConfig,
  ~fs,
  ~path,
  ~process,
  ~shell,
) => {
  let count = ref(0)
  let tmpFiles: array<string> = []

  // Build safe env for child process execution
  let envFilterConfig = shellConfig->Option.flatMap(s => s.env->Option.map(ShellBuilder.buildEnvFilterConfig))
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, process.env())

  let promise = commands->Array.reduce(Promise.resolve(Ok()), (acc, cmd) => {
    acc->Promise.then(r => {
      switch r {
      | Error(_) => Promise.resolve(r)
      | Ok(_) =>
        switch cmd.target {
        | Fetch(url) => executeFetch(
            ~url,
            ~stagingDir,
            ~path,
            ~fs,
            ~tmpFiles,
            ~countRef=count,
          )
        | ToolCall({name, toolDef}) => executeToolCall(
            ~name,
            ~toolDef,
            ~cwd,
            ~safeEnv,
            ~shellConfig,
            ~shell,
            ~countRef=count,
          )
        | InlineCommand(command) => executeInlineCommand(
            ~command,
            ~cwd,
            ~path,
            ~fs,
            ~shellConfig,
            ~shell,
            ~countRef=count,
          )
        | ScriptFile(cmdPath) => executeScriptFile(
            ~cmdPath,
            ~cwd,
            ~path,
            ~fs,
            ~safeEnv,
            ~shell,
            ~countRef=count,
          )
        }
      }
    })
  })
  let finish = r =>
    Promise.resolve(switch r {
    | Ok(_) => Ok(count.contents)
    | Error(e) => Error(e)
    })
  promise
  ->Promise.then(r => cleanupFetchTmpFiles(tmpFiles, ~fs)->Promise.then(_ => finish(r)))
  ->Promise.catch(e => {
    let msg = Errors.extractErrorMessage(e)
    cleanupFetchTmpFiles(tmpFiles, ~fs)->Promise.then(_ => finish(Error(msg)))
  })
}
