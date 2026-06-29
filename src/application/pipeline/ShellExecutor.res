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

let buildEnvFilterConfig: Config.shellEnv => EnvFilter.shellEnvConfig = e => {
  let entries: array<EnvFilter.shellEnvEntry> = e.vars->Dict.toArray->Array.map(((k, v)) => {
    let entry: EnvFilter.shellEnvEntry = {key: k, value: v}
    entry
  })
  {vars: entries}
}

// Execute all queued shell commands
let executeShellCommands: (
  ~commands: array<shellCommand>,
  ~cwd: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
) => promise<result<(int, array<string>), string>> = (
  ~commands,
  ~cwd,
  ~shellConfig,
  ~fs,
  ~path,
  ~process,
  ~shell,
) => {
  let count = ref(0)
  let tmpFiles: array<string> = []

  // Build safe env for child process execution
  let envFilterConfig: option<EnvFilter.shellEnvConfig> = shellConfig->Option.flatMap(s => {
    switch s.env {
    | Some(e) => Some(buildEnvFilterConfig(e))
    | None => None
    }
  })
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, process.env())

  let promise = commands->Array.reduce(Promise.resolve(Ok()), (acc, cmd) => {
    acc->Promise.then(r => {
      switch r {
      | Error(_) => Promise.resolve(r)
      | Ok(_) =>
        switch cmd.target {
        | Fetch(url) => {
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
                  let fetchPath = path.join(cwd, fetchFileName)
                  fs.writeFile(fetchPath, content)->Promise.then(_ => {
                    let _ = tmpFiles->Array.push(fetchPath)
                    count.contents = count.contents + 1
                    Promise.resolve(Ok())
                  })->Promise.catch(_ => {
                    Promise.resolve(Error("Failed to write fetched content: " ++ url))
                  })
                }
              | Error(msg) => {
                  Promise.resolve(Error("Fetch failed: " ++ msg))
                }
              }
            })
          }
        | ToolCall({name, toolDef}) => {
            // WS2: route through ExecPolicy — args[] → ExecFile (no shell);
            // no-args + tools allowlist match → ShellExact; otherwise Reject.
            let toolsAllowlist: array<string> = shellConfig
              ->Option.flatMap(cfg => cfg.tools)
              ->Option.getOr([])
              ->Array.map(tool => tool.command)
            switch ExecPolicy.decide(~command=toolDef.command, ~args=toolDef.args, ~allowlist=toolsAllowlist) {
            | Reject(reason) => Promise.resolve(Error(reason))
            | ExecFile(command, args) => {
                let execFileOpts: Ports.shellOptions = {
                  cwd: cwd,
                  env: safeEnv,
                  encoding: "utf8",
                  timeout: ExecPolicy.defaultTimeout,
                }
                shell.execFileAsync(command, ~args, ~options=execFileOpts)->Promise.then(result => {
                  if result.killed {
                    Promise.resolve(Error("Tool '" ++ name ++ "' timed out after " ++ Int.toString(ExecPolicy.defaultTimeout) ++ "ms"))
                  } else {
                    switch result.status {
                    | Some(0) => {
                        count.contents = count.contents + 1
                        Promise.resolve(Ok())
                      }
                    | status => {
                        Promise.resolve(Error("Tool '" ++ name ++ "' exited with code: " ++ Int.toString(status->Option.getOr(-1))))
                      }
                    }
                  }
                })->Promise.catch(_ => {
                  Promise.resolve(Error("Tool '" ++ name ++ "' execution failed"))
                })
              }
            | ShellExact(command) => {
                let shellOpts: Ports.shellOptions = {
                  cwd: cwd,
                  env: safeEnv,
                  shell: true,
                  encoding: "utf8",
                  timeout: ExecPolicy.defaultTimeout,
                }
                shell.execAsync(command, ~options=shellOpts)->Promise.then(result => {
                  if result.killed {
                    Promise.resolve(Error("Tool '" ++ name ++ "' timed out after " ++ Int.toString(ExecPolicy.defaultTimeout) ++ "ms"))
                  } else {
                    switch result.status {
                    | Some(0) => {
                        count.contents = count.contents + 1
                        Promise.resolve(Ok())
                      }
                    | status => {
                        Promise.resolve(Error("Tool '" ++ name ++ "' exited with code: " ++ Int.toString(status->Option.getOr(-1))))
                      }
                    }
                  }
                })->Promise.catch(_ => {
                  Promise.resolve(Error("Tool '" ++ name ++ "' execution failed"))
                })
              }
            }
          }
        | InlineCommand(command) => {
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
                    shell.execShellCommand(~command, ~cwd)->Promise.then(result => {
                      switch result {
                        | Ok(_) => {
                            count.contents = count.contents + 1
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
        | ScriptFile(cmdPath) => {
            let resolvedPath = path.resolve(cmdPath, "")
            PathSecurity.isWithinTree(resolvedPath, cwd, path, fs)->Promise.then(isWithin => {
              if !isWithin {
                Promise.resolve(Error("Script path outside project tree: " ++ cmdPath))
              } else {
                fs.fileExists(resolvedPath)->Promise.then(exists => {
                  if !exists {
                    Promise.resolve(Error("Script file not found: " ++ cmdPath))
                  } else {
                    let execOpts: Ports.shellOptions = {
                      cwd: cwd,
                      env: safeEnv,
                      shell: true,
                      encoding: "utf8",
                      timeout: ExecPolicy.defaultTimeout,
                    }
                    shell.execAsync(resolvedPath, ~options=execOpts)->Promise.then(result => {
                      if result.killed {
                        Promise.resolve(Error("Script timed out after " ++ Int.toString(ExecPolicy.defaultTimeout) ++ "ms: " ++ cmdPath))
                      } else {
                        switch result.status {
                        | Some(0) => {
                            count.contents = count.contents + 1
                            Promise.resolve(Ok())
                          }
                        | status => {
                            Promise.resolve(Error("Script exited with code " ++ Int.toString(status->Option.getOr(-1)) ++ ": " ++ cmdPath))
                          }
                        }
                      }
                    })->Promise.catch(e => {
                      let msg = switch JsExn.message(e->Obj.magic) {
                      | Some(m) => m
                      | None => "unknown"
                      }
                      Promise.resolve(Error("Script execution failed: " ++ msg ++ " (" ++ cmdPath ++ ")"))
                    })
                  }
                })
              }
            })
          }
        }
      }
    })
  })
  promise->Promise.then(r => {
    cleanupFetchTmpFiles(tmpFiles, ~fs)->Promise.then(_ => {
      Promise.resolve(switch r {
      | Ok(_) => Ok((count.contents, []))
      | Error(e) => Error(e)
      })
    })
  })
}
