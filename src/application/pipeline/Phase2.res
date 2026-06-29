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

type backupEntry = {
  outputPath: string,
  backupPath: string,
}

type phase2Error = {
  message: string,
  partialCommit?: array<string>, // files that were committed before error
  catastrophic?: bool,
  failedRollbackFiles?: array<string>,
}

// Re-exported aliases so tests + external callers using these Phase2 entrypoints keep compiling.
// Wrappers coerce Commit's nominal types to Phase2's structurally identical types at the boundary.
let executeShellCommands = ShellExecutor.executeShellCommands

let rollbackOutput: (
  ~committedFiles: array<string>,
  ~backups: array<backupEntry>,
  ~fs: Ports.fileSystem,
) => promise<result<unit, array<string>>> = (~committedFiles, ~backups, ~fs) => {
  let commitBackups: array<Commit.backupEntry> = backups->Array.map(b => (b :> Commit.backupEntry))
  Commit.rollbackOutput(~committedFiles, ~backups=commitBackups, ~fs)
}

let rollback = Commit.rollback

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
  // Coerce Commit's nominal types (backupEntry, phase2Error) to Phase2's at the boundary.
  let commitResult: result<(int, array<backupEntry>), phase2Error> = switch await Commit.commitFiles(
    ~stagingDir,
    ~outputDir,
    ~renderedFiles,
    ~fs,
    ~path,
  ) {
  | Ok((count, backups)) =>
    let phase2Backups: array<backupEntry> = backups->Array.map(b => (b :> backupEntry))
    Ok((count, phase2Backups))
  | Error(e) => Error((e :> phase2Error))
  }

  switch commitResult {
  | Ok((count, backups)) => {
      // Execute shell commands
      let shellResult = await ShellExecutor.executeShellCommands(
        ~commands=shellCommands,
        ~cwd=outputDir,
        ~stagingDir,
        ~shellConfig,
        ~fs,
        ~path,
        ~process,
        ~shell,
      )

      switch shellResult {
      | Ok((cmdsExec, shellErrors)) => {
          let _ = await Commit.rollback(stagingDir, ~fs)

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
            switch await Commit.rollback(stagingDir, ~fs) {
            | Ok() => {
                let err: phase2Error = {message, partialCommit: committedFiles}
                Error(err)
              }
            | Error(rollbackMessage) =>
              let err: phase2Error = {
                message: message ++ " | rollback failed: " ++ rollbackMessage,
                partialCommit: committedFiles,
                catastrophic: true,
              }
              Error(err)
            }
          | Error(failedRollbackFiles) => {
              let catastrophicError: phase2Error = {
                message,
                partialCommit: committedFiles,
                catastrophic: true,
                failedRollbackFiles,
              }

              switch await Commit.rollback(stagingDir, ~fs) {
              | Ok() => Error(catastrophicError)
              | Error(rollbackMessage) => {
                  let err: phase2Error = {
                    ...catastrophicError,
                    message: message ++ " | rollback failed: " ++ rollbackMessage,
                  }
                  Error(err)
                }
              }
            }
          }
        }
      }
    }
  | Error(err) => {
      // Commit failed — rollback
      switch await Commit.rollback(stagingDir, ~fs) {
      | Ok() => Error(err)
      | Error(rollbackMessage) => {
          let e: phase2Error = {
            ...err,
            message: err.message ++ " | rollback failed: " ++ rollbackMessage,
            catastrophic: true,
          }
          Error(e)
        }
      }
    }
  }
}
