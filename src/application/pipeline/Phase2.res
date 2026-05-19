// Phase2: Atomic commit from staging to output, rollback on failure
// Mirrors Go version's phase2/phase2.go

open Bindings
open Template

type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
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
) => promise<result<int, string>> = (~commands, ~cwd, ~shellConfig) => {
  let count = ref(0)

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
  let safeEnv = EnvFilter.buildSafeEnv(envFilterConfig, NodeJs.NodeProcess.env->Obj.magic)

  let promise = commands->Array.reduce(Promise.resolve(Ok()), (acc, cmd) => {
    acc->Promise.then(r => {
      switch r {
      | Error(e) => Promise.resolve(Error(e))
      | Ok(_) =>
        switch cmd.target {
        | Fetch(url) => {
            // Fetch URL content and write to staging file
            Fetcher.fetch(url)->Promise.then(result => {
              switch result {
              | Ok(content) => {
                  // Write fetched content to a file in cwd
                  let fetchFileName = {
                    // Generate a unique filename based on URL
                    let hash = url->String.split("")->Array.reduce(0, (acc, c) => {
                      let code = switch String.charCodeAt(c, 0) {
                      | Some(n) => n
                      | None => 0
                      }
                      acc + code
                    })
                    "fetch-" ++ Int.toString(hash) ++ ".tmp"
                  }
                  let fetchPath = Path.join(cwd, fetchFileName)
                  Fs.writeFile(fetchPath, content)->Promise.then(_ => {
                    count.contents = count.contents + 1
                    Promise.resolve(Ok())
                  })->Promise.catch(_ => {
                    Promise.resolve(Error("Failed to write fetched content: " ++ url))
                  })
                }
              | Error(msg) => Promise.resolve(Error("Fetch failed: " ++ msg))
              }
            })
          }
        | ToolCall({toolDef}) => {
            // Execute tool via exec with shell:true (safer than raw execFile for tools)
            let execOpts: Bindings.ChildProcess.execOptions = {
              cwd: cwd,
              env: safeEnv,
              shell: true,
              encoding: "utf8",
            }
            // Build the full command from toolDef
            let fullCommand = switch toolDef.args {
            | Some(args) => toolDef.command ++ " " ++ args->Array.join(" ")
            | None => toolDef.command
            }
            ChildProcess.exec(fullCommand, ~options=execOpts)->Promise.then(result => {
              switch result.status {
              | Some(0) => {
                  count.contents = count.contents + 1
                  Promise.resolve(Ok())
                }
              | status =>
                Promise.resolve(Error("Tool exited with code: " ++ Int.toString(status->Option.getOr(-1))))
              }
            })->Promise.catch(_ => {
              Promise.resolve(Error("Tool execution failed"))
            })
          }
        | InlineCommand(command) => {
            let shellEnabled = switch shellConfig {
            | Some(cfg) => cfg.enabled
            | None => false
            }
            if !shellEnabled {
              Promise.resolve(Error("Shell execution disabled"))
            } else {
              // Allowlist validation: command's first token must match a tool.command
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
                ChildProcess.execShellCommand(~command, ~cwd)->Promise.then(result => {
                  switch result {
                  | Ok(_) => {
                      count.contents = count.contents + 1
                      Promise.resolve(Ok())
                    }
                  | Error(e) => Promise.resolve(Error("Shell command failed: " ++ e))
                  }
                })
              }
            }
          }
        | ScriptFile(path) =>
          // ScriptFile is deprecated - scripts must be declared as tools
          Promise.resolve(Error("Scripts must be declared as tools: " ++ path))
        }
      }
    })
  })
  promise->Promise.then(r => {
    switch r {
    | Ok(_) => Promise.resolve(Ok(count.contents))
    | Error(e) => Promise.resolve(Error(e))
    }
  })
}

// Copy staged files to output directory
let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
) => promise<result<int, phase2Error>> = async (~stagingDir, ~outputDir, ~renderedFiles) => {
  let partialCommit: array<string> = []
  let errorRef: ref<option<string>> = ref(None)

  let _ = await renderedFiles->Array.reduce(
    Promise.resolve(),
    async (acc, (_, targetPath)) => {
      let _ = await acc
      
      switch errorRef.contents {
      | Some(_) => ()
      | None =>
        let stagedPath = Path.join(stagingDir, targetPath)
        let destPath = Path.join(outputDir, targetPath)
        let destDir = Path.dirname(destPath)
        try {
          let _ = await Fs.mkdir(destDir, ~options={recursive: true})
          await Fs.cp(stagedPath, destPath, ~options={recursive: false})
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
let rollback: string => promise<unit> = async stagingDir => {
  try {
    await Fs.rm(stagingDir, ~options={recursive: true})
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
) => promise<result<phase2Result, phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
  ~shellCommands,
  ~shellConfig,
) => {
  // Commit files
  let commitResult = await commitFiles(~stagingDir, ~outputDir, ~renderedFiles)

  switch commitResult {
  | Ok(count) => {
      // Execute shell commands
      let shellResult = await executeShellCommands(~commands=shellCommands, ~cwd=outputDir, ~shellConfig)

      switch shellResult {
      | Ok(cmdsExec) => {
          // Cleanup staging dir
          await rollback(stagingDir)

          Ok({
            filesCreated: count,
            filesInjected: 0,
            commandsExecuted: cmdsExec,
          })
        }
      | Error(_e) =>
        // Shell failed but files committed — return partial success
        Ok({
          filesCreated: count,
          filesInjected: 0,
          commandsExecuted: 0,
        })
      }
    }
  | Error(err) => {
      // Commit failed — rollback
      await rollback(stagingDir)
      Error(err)
    }
  }
}
