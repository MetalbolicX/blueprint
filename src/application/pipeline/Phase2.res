// Phase2: Atomic commit from staging to output, rollback on failure.
// Thin orchestrator over ShellExecutor and Commit sub-modules.
// Mirrors Go version's phase2/phase2.go

open Template
open Commit

type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
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
  ~fetcher: Ports.fetcher,
  ~pathSecurity: Ports.pathSecurity,
  ~shellBuilder: Ports.shellBuilder,
  ~envFilter: Ports.envFilter,
  ~tmpRoot: string=?,
  ~commitRollbackRef: ref<option<unit => promise<unit>>>=?,
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
  ~fetcher,
  ~pathSecurity,
  ~shellBuilder,
  ~envFilter,
  ~tmpRoot=?,
  ~commitRollbackRef=?,
) => {
  let tmpRoot = tmpRoot->Option.getOr(path.dirname(stagingDir))
  let committingFiles: ref<array<string>> = ref([])
  let committingBackups: ref<array<backupEntry>> = ref([])
  let committingDirs: ref<array<string>> = ref([])
  let setRollback = switch commitRollbackRef {
  | Some(stateRef) => Some(stateRef)
  | None => None
  }
  switch setRollback {
  | Some(stateRef) => stateRef.contents = Some(() => Commit.rollbackOutput(
      ~committedFiles=committingFiles.contents,
      ~backups=committingBackups.contents,
      ~createdDirs=committingDirs.contents,
      ~outputDir,
      ~path,
      ~fs,
      ~pathSecurity,
    )->Promise.then(result => {
        // A failed signal-time rollback must not exit silently: the output
        // tree may be partially committed with its backups about to be
        // deleted alongside staging, so surface every failed path.
        switch result {
        | Ok(_) => ()
        | Error(failures) => {
            let paths = failures->Array.map(f => f.path)
            Console.error(
              "Signal rollback failed — output may be partially committed: "
              ++ Js.Array.joinWith(", ", paths),
            )
          }
        }
        Promise.resolve()
      })->Promise.catch(_ => {
      Console.error("Signal rollback failed — output may be partially committed")
      Promise.resolve()
    }))
  | None => ()
  }

  let committedFiles = renderedFiles->Array.map(((_, targetPath)) => path.join(outputDir, targetPath))

  // Commit files
  let commitResult = await Commit.commitFiles(
    ~stagingDir,
    ~outputDir,
    ~renderedFiles,
    ~fs,
    ~path,
    ~pathSecurity,
    ~onCommitting=((outputPath, backupOpt) => {
      committingFiles.contents->Array.push(outputPath)->ignore
      switch backupOpt {
      | Some(backup) => committingBackups.contents->Array.push(backup)->ignore
      | None => ()
      }
    }),
    ~onCreatedDirs=(dirs => committingDirs.contents = dirs),
  )
  switch setRollback {
  | Some(stateRef) => stateRef.contents = None
  | None => ()
  }

  switch commitResult {
  | Ok((count, backups, createdDirs)) => {
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
        ~fetcher,
        ~pathSecurity,
        ~shellBuilder,
        ~envFilter,
      )

      switch shellResult {
      | Ok(cmdsExec) => {
          switch await Commit.rollback(stagingDir, ~tmpRoot, ~path, ~fs, ~pathSecurity) {
          | Ok() => ()
          | Error(message) => Console.warn("Warning: could not clean staging directory " ++ stagingDir ++ ": " ++ message)
          }

          let result: phase2Result = {
            filesCreated: count,
            filesInjected: 0,
            commandsExecuted: cmdsExec,
          }
          Ok(result)
        }
      | Error(message) => {
          switch await Commit.rollbackOutput(~committedFiles, ~backups, ~createdDirs, ~outputDir, ~path, ~fs, ~pathSecurity) {
          | Ok() =>
            switch await Commit.rollback(stagingDir, ~tmpRoot, ~path, ~fs, ~pathSecurity) {
            | Ok() => {
                let err: phase2Error = {message, partialCommit: ?None}
                Error(err)
              }
            | Error(rollbackMessage) =>
              let err: phase2Error = {
                message: message ++ " | rollback failed: " ++ rollbackMessage,
                partialCommit: ?None,
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

              switch await Commit.rollback(stagingDir, ~tmpRoot, ~path, ~fs, ~pathSecurity) {
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
      let rollbackTargets = err.partialCommit->Option.getOr([])->Array.concat(err.failedTargets->Option.getOr([]))
      let rollbackBackups = err.backups->Option.getOr([])->Array.concat(err.failedBackups->Option.getOr([]))
      let rollbackDirs = err.createdDirs->Option.getOr([])
      switch await Commit.rollbackOutput(
        ~committedFiles=rollbackTargets,
        ~backups=rollbackBackups,
        ~createdDirs=rollbackDirs,
        ~outputDir,
        ~path,
        ~fs,
        ~pathSecurity,
      ) {
      | Ok() =>
        switch await Commit.rollback(stagingDir, ~tmpRoot, ~path, ~fs, ~pathSecurity) {
        | Ok() => Error({...err, partialCommit: ?None})
        | Error(rollbackMessage) => {
            let e: phase2Error = {
              ...err,
              message: err.message ++ " | rollback failed: " ++ rollbackMessage,
              partialCommit: ?None,
              catastrophic: true,
            }
            Error(e)
          }
        }
      | Error(failedRollbackFiles) => {
          let failedPaths = failedRollbackFiles->Array.map(f => f.path)
          let catastrophicError: phase2Error = {
            ...err,
            catastrophic: true,
            failedRollbackFiles: ?Some(failedPaths),
          }
          switch await Commit.rollback(stagingDir, ~tmpRoot, ~path, ~fs, ~pathSecurity) {
          | Ok() => Error(catastrophicError)
          | Error(rollbackMessage) =>
            Error({...catastrophicError, message: err.message ++ " | rollback failed: " ++ rollbackMessage})
          }
        }
      }
    }
  }
}
