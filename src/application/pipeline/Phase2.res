// Phase2: Atomic commit from staging to output, rollback on failure.
// Thin orchestrator over ShellExecutor and Commit sub-modules.
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
  catastrophic?: bool,
  failedRollbackFiles?: array<string>,
}

type backupEntry = {
  outputPath: string,
  backupPath: string,
}

let backupDirName = ".blueprint-backup"

// Re-exported alias so tests + external callers using `Phase2.executeShellCommands` keep compiling.
let executeShellCommands = ShellExecutor.executeShellCommands

let backupIfOverwriting: (
  ~targetPath: string,
  ~outputDir: string,
  ~stagingDir: string,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<option<backupEntry>, string>> = async (~targetPath, ~outputDir, ~stagingDir, ~fs, ~path) => {
  let destPath = path.join(outputDir, targetPath)
  let exists = await fs.fileExists(destPath)
  if !exists {
    Ok(None)
  } else {
    let backupPath = path.join(stagingDir, path.join(backupDirName, targetPath))
    let backupDir = path.dirname(backupPath)
    try {
      let _ = await fs.mkdir(backupDir, ~options={recursive: true})
      await fs.cp(destPath, backupPath, ~options={recursive: false})
      Ok(Some({outputPath: destPath, backupPath}))
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Backup failed"
      }
      Error("Failed to backup existing output " ++ targetPath ++ ": " ++ msg)
    }
  }
}

// Copy staged files to output directory
let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<(int, array<backupEntry>), phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
  ~fs,
  ~path,
) => {
  let partialCommit: array<string> = []
  let backups: array<backupEntry> = []
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
        switch await backupIfOverwriting(~targetPath, ~outputDir, ~stagingDir, ~fs, ~path) {
        | Error(e) => errorRef.contents = Some(e)
        | Ok(backupOpt) =>
          backupOpt->Option.forEach(entry => {
            let _ = backups->Array.push(entry)
          })
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
  | None => Ok((Array.length(partialCommit), backups))
  }
}

let rollbackOutput: (
  ~committedFiles: array<string>,
  ~backups: array<backupEntry>,
  ~fs: Ports.fileSystem,
) => promise<result<unit, array<string>>> = async (~committedFiles, ~backups, ~fs) => {
  let failedPaths: array<string> = []
  let _ = await committedFiles->Array.reduce(Promise.resolve(), (acc, outputPath) => {
    acc->Promise.then(async _ => {
      switch backups->Array.find(b => b.outputPath == outputPath) {
      | Some(backup) => {
          try {
            await fs.cp(backup.backupPath, outputPath, ~options={recursive: false})
          } catch {
          | _ => failedPaths->Array.push(outputPath)->ignore
          }
        }
      | None => {
          try {
            await fs.rm(outputPath, ~options={recursive: false})
          } catch {
          | _ => failedPaths->Array.push(outputPath)->ignore
          }
        }
      }
    })
  })

  switch failedPaths->Array.length {
  | 0 => Ok()
  | _ => Error(failedPaths)
  }
}

// Rollback: remove staging directory
let rollback: (string, ~fs: Ports.fileSystem) => promise<result<unit, string>> = async (stagingDir, ~fs) => {
  try {
    await fs.rm(stagingDir, ~options={recursive: true})
    Ok()
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(message) => message
    | None => "Failed to remove staging directory"
    }
    Error(msg)
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
  let committedFiles = renderedFiles->Array.map(((_, targetPath)) => path.join(outputDir, targetPath))

  // Commit files
  let commitResult = await commitFiles(~stagingDir, ~outputDir, ~renderedFiles, ~fs, ~path)

  switch commitResult {
  | Ok((count, backups)) => {
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
          let _ = await rollback(stagingDir, ~fs)

          let shellErrs: option<array<string>> = shellErrors->Array.length > 0 ? Some(shellErrors) : None
          let result: phase2Result = {
            filesCreated: count,
            filesInjected: 0,
            commandsExecuted: cmdsExec,
            shellErrors: ?shellErrs,
          }
          Ok(result)
        }
      | Error(message) => {
          switch await rollbackOutput(~committedFiles, ~backups, ~fs) {
          | Ok() =>
            switch await rollback(stagingDir, ~fs) {
            | Ok() => Error({message, partialCommit: committedFiles})
            | Error(rollbackMessage) =>
              Error({
                message: message ++ " | rollback failed: " ++ rollbackMessage,
                partialCommit: committedFiles,
                catastrophic: true,
              })
            }
          | Error(failedRollbackFiles) => {
              let catastrophicError: phase2Error = {
                message,
                partialCommit: committedFiles,
                catastrophic: true,
                failedRollbackFiles,
              }

              switch await rollback(stagingDir, ~fs) {
              | Ok() => Error(catastrophicError)
              | Error(rollbackMessage) =>
                Error({...catastrophicError, message: message ++ " | rollback failed: " ++ rollbackMessage})
              }
            }
          }
        }
      }
    }
  | Error(err) => {
      // Commit failed — rollback
      switch await rollback(stagingDir, ~fs) {
      | Ok() => Error(err)
      | Error(rollbackMessage) =>
        Error({
          ...err,
          message: err.message ++ " | rollback failed: " ++ rollbackMessage,
          catastrophic: true,
        })
      }
    }
  }
}
