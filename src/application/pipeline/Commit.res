// Commit: Phase2 backup, commit, and rollback helpers.
// Owns the backup-before-overwrite logic, the atomic commit loop, and the rollback paths.
// Owns the canonical `backupEntry` and `phase2Error` type definitions (Phase2 re-exports aliases).
// No imports of other phase sub-modules — sits below Phase2 in the dependency arrow.

type backupEntry = {
  outputPath: string,
  backupPath: string,
}

type phase2Error = {
  message: string,
  partialCommit?: array<string>,
  catastrophic?: bool,
  failedRollbackFiles?: array<string>,
}

let backupDirName = ".blueprint-backup"

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

        // WS1 defensive reject: even if TemplateRenderer.render was bypassed,
        // never commit to a target that already escaped the output tree.
        let isWithin = await PathSecurity.isWithinTree(destPath, outputDir, path, fs)
        if !isWithin {
          errorRef.contents = Some("Target path outside output tree: " ++ targetPath)
        } else {
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
