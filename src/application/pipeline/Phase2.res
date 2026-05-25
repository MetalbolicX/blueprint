// Phase2: Atomic commit from staging to output, rollback on failure
// Mirrors Go version's phase2/phase2.go

open Template

type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  shellErrors?: array<string>,
}

type phase2Error = {
  message: string,
  partialCommit?: array<string>, // files that were committed before error
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
  let errors: array<string> = []

  // Build safe env for child process execution
  let buildEnvFilterConfig: Config.shellEnv => EnvFilter.shellEnvConfig = e => {
    let entries: array<EnvFilter.shellEnvEntry> = e.vars->Dict.toArray->Array.map(((k, v)) => {
      let entry: EnvFilter.shellEnvEntry = {key: k, value: v}
      entry
    })
    {vars: entries}
  }
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
                    let hash = url->String.split("")->Array.reduce(0, (acc, c) => {
                      let code = switch String.charCodeAt(c, 0) {
                      | Some(n) => n
                      | None => 0
                      }
                      acc + code
                    })
                    "fetch-" ++ Int.toString(hash) ++ ".tmp"
                  }
                  let fetchPath = path.join(cwd, fetchFileName)
                  fs.writeFile(fetchPath, content)->Promise.then(_ => {
                    count.contents = count.contents + 1
                    Promise.resolve(Ok())
                  })->Promise.catch(_ => {
                    errors->Array.push("Failed to write fetched content: " ++ url)
                    Promise.resolve(Ok())
                  })
                }
              | Error(msg) => {
                  errors->Array.push("Fetch failed: " ++ msg)
                  Promise.resolve(Ok())
                }
              }
            })
          }
        | ToolCall({name, toolDef}) => {
            let execOpts: Ports.shellOptions = {
              cwd: cwd,
              env: safeEnv,
              shell: true,
              encoding: "utf8",
            }
            let fullCommand = switch toolDef.args {
            | Some(args) => toolDef.command ++ " " ++ args->Array.join(" ")
            | None => toolDef.command
            }
            shell.execAsync(fullCommand, ~options=execOpts)->Promise.then(result => {
              switch result.status {
              | Some(0) => {
                  count.contents = count.contents + 1
                  Promise.resolve(Ok())
                }
              | status => {
                  errors->Array.push("Tool '" ++ name ++ "' exited with code: " ++ Int.toString(status->Option.getOr(-1)))
                  Promise.resolve(Ok())
                }
              }
            })->Promise.catch(_ => {
              errors->Array.push("Tool '" ++ name ++ "' execution failed")
              Promise.resolve(Ok())
            })
          }
        | InlineCommand(command) => {
            let shellEnabled = switch shellConfig {
            | Some(cfg) => cfg.enabled
            | None => false
            }
            if !shellEnabled {
              errors->Array.push("Shell execution disabled")
              Promise.resolve(Ok())
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
                errors->Array.push("Command not in tools allowlist: " ++ command)
                Promise.resolve(Ok())
              } else {
                let resolvedCmd = path.resolve(cwd, baseCmd)
                if !PathSecurity.isWithinTree(resolvedCmd, cwd, path) {
                  errors->Array.push("Command path outside project tree: " ++ baseCmd)
                  Promise.resolve(Ok())
                } else {
                  shell.execShellCommand(~command, ~cwd)->Promise.then(result => {
                    switch result {
                    | Ok(_) => {
                        count.contents = count.contents + 1
                        Promise.resolve(Ok())
                      }
                    | Error(e) => {
                        errors->Array.push("Shell command failed: " ++ e)
                        Promise.resolve(Ok())
                      }
                    }
                  })
                }
              }
            }
          }
        | ScriptFile(cmdPath) => {
            let resolvedPath = path.resolve(cmdPath, "")
            if !PathSecurity.isWithinTree(resolvedPath, cwd, path) {
              errors->Array.push("Script path outside project tree: " ++ cmdPath)
              Promise.resolve(Ok())
            } else {
              fs.fileExists(resolvedPath)->Promise.then(exists => {
                if !exists {
                  errors->Array.push("Script file not found: " ++ cmdPath)
                  Promise.resolve(Ok())
                } else {
                  let execOpts: Ports.shellOptions = {
                    cwd: cwd,
                    env: safeEnv,
                    shell: true,
                    encoding: "utf8",
                  }
                  shell.execAsync(resolvedPath, ~options=execOpts)->Promise.then(result => {
                    if result.killed {
                      errors->Array.push("Script timed out and was killed: " ++ cmdPath)
                      Promise.resolve(Ok())
                    } else {
                      switch result.status {
                      | Some(0) => {
                          count.contents = count.contents + 1
                          Promise.resolve(Ok())
                        }
                      | status => {
                          errors->Array.push("Script exited with code " ++ Int.toString(status->Option.getOr(-1)) ++ ": " ++ cmdPath)
                          Promise.resolve(Ok())
                        }
                      }
                    }
                  })->Promise.catch(e => {
                    let msg = switch JsExn.message(e->Obj.magic) {
                    | Some(m) => m
                    | None => "unknown"
                    }
                    errors->Array.push("Script execution failed: " ++ msg ++ " (" ++ cmdPath ++ ")")
                    Promise.resolve(Ok())
                  })
                }
              })
            }
          }
        }
      }
    })
  })
  promise->Promise.then(r => {
    switch r {
    | Ok(_) => Promise.resolve(Ok((count.contents, errors)))
    | Error(e) => Promise.resolve(Error(e))
    }
  })
}

// Copy staged files to output directory
let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<int, phase2Error>> = async (~stagingDir, ~outputDir, ~renderedFiles, ~fs, ~path) => {
  let partialCommit: array<string> = []
  let errorRef: ref<option<string>> = ref(None)

  let _ = await renderedFiles->Array.reduce(
    Promise.resolve(),
    async (acc, (_, targetPath)) => {
      let _ = await acc

      switch errorRef.contents {
      | Some(_) => ()
      | None =>
        let stagedPath = path.join(stagingDir, targetPath)
        let destPath = path.join(outputDir, targetPath)
        let destDir = path.dirname(destPath)
        try {
          let _ = await fs.mkdir(destDir, ~options={recursive: true})
          await fs.cp(stagedPath, destPath, ~options={recursive: false})
          let _ = partialCommit->Array.push(destPath)
        } catch {
        | JsExn(obj) =>
          let msg = switch JsExn.message(obj) {
          | Some(m) => m
          | None => "Copy failed"
          }
          errorRef.contents = Some("Failed to commit " ++ targetPath ++ ": " ++ msg)
        }
      }
    },
  )

  let partial = switch partialCommit->Array.length {
  | 0 => None
  | _ => Some(partialCommit)
  }

  switch errorRef.contents {
  | Some(msg) =>
    let err: phase2Error = {message: msg}
    switch partial {
    | Some(files) => Error({message: msg, partialCommit: files})
    | None => Error(err)
    }
  | None => Ok(Array.length(partialCommit))
  }
}

// Rollback: remove staging directory
let rollback: (string, ~fs: Ports.fileSystem) => promise<unit> = async (stagingDir, ~fs) => {
  try {
    await fs.rm(stagingDir, ~options={recursive: true})
  } catch {
  | _ => ()
  }
}

// Run Phase2: commit staged files to output, execute shell commands
let run: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~shellCommands: array<shellCommand>,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
) => promise<result<phase2Result, phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
  ~shellCommands,
  ~shellConfig,
  ~fs,
  ~path,
  ~process,
  ~shell,
) => {
  // Commit files
  let commitResult = await commitFiles(~stagingDir, ~outputDir, ~renderedFiles, ~fs, ~path)

  switch commitResult {
  | Ok(count) => {
      // Execute shell commands
      let shellResult = await executeShellCommands(
        ~commands=shellCommands,
        ~cwd=outputDir,
        ~shellConfig,
        ~fs,
        ~path,
        ~process,
        ~shell,
      )

      switch shellResult {
      | Ok((cmdsExec, shellErrors)) => {
          await rollback(stagingDir, ~fs)

          let shellErrs: option<array<string>> = shellErrors->Array.length > 0 ? Some(shellErrors) : None
          let result: phase2Result = {
            filesCreated: count,
            filesInjected: 0,
            commandsExecuted: cmdsExec,
            shellErrors: ?shellErrs,
          }
          await rollback(stagingDir, ~fs)
          Ok(result)
        }
      | Error(_e) =>
        await rollback(stagingDir, ~fs)
        Ok({
          filesCreated: count,
          filesInjected: 0,
          commandsExecuted: 0,
        })
      }
    }
  | Error(err) => {
      // Commit failed — rollback
      await rollback(stagingDir, ~fs)
      Error(err)
    }
  }
}