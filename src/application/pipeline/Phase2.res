// Phase2: Atomic commit from staging to output, rollback on failure.
// Thin orchestrator over ShellExecutor and Commit sub-modules.
// Mirrors Go version's phase2/phase2.go

open Template
open Commit

type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  shellErrors?: array<string>,
}

let executeShellCommands = ShellExecutor.executeShellCommands

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
  let commitResult = await Commit.commitFiles(
    ~stagingDir,
    ~outputDir,
    ~renderedFiles,
    ~fs,
    ~path,
  )

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
          switch await Commit.rollbackOutput(~committedFiles, ~backups, ~fs) {
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
              let failedPaths = failedRollbackFiles->Array.map(f => f.path)
              let catastrophicError: phase2Error = {
                message,
                partialCommit: committedFiles,
                catastrophic: true,
                failedRollbackFiles: failedPaths,
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
