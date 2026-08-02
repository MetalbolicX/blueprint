// Commit: Phase2 backup, commit, and rollback helpers.
// Owns the backup-before-overwrite logic, the atomic commit loop, and the rollback paths.
// Owns the canonical `backupEntry` and `phase2Error` type definitions (Phase2 re-exports aliases).
// No imports of other phase sub-modules — sits below Phase2 in the dependency arrow.

type backupEntry = {
  outputPath: string,
  backupPath: string,
}

type rollbackFailure = {
  path: string,
  reason: string,
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
  let seenTargets: ref<dict<string>> = ref(Dict.make())
  let dedupedFiles = renderedFiles->Array.filter(((_, targetPath)) => {
    if seenTargets.contents->Dict.has(targetPath) {
      Console.warn("Duplicate target path: " ++ targetPath ++ " — skipping")
      false
    } else {
      let _ = seenTargets.contents->Dict.set(targetPath, targetPath)
      true
    }
  })

  let workItems = dedupedFiles->Array.map(((_, targetPath)) => async () => {
    let stagedPath = path.join(stagingDir, targetPath)
    let destPath = path.join(outputDir, targetPath)
    let destDir = path.dirname(destPath)

    let isWithin = await PathSecurity.isWithinTree(destPath, outputDir, path, fs)
    if !isWithin {
      Error(("Target path outside output tree: " ++ targetPath, None))
    } else {
      switch await backupIfOverwriting(~targetPath, ~outputDir, ~stagingDir, ~fs, ~path) {
      | Error(e) => Error((e, None))
      | Ok(backupOpt) => {
          try {
            let _ = await fs.mkdir(destDir, ~options={recursive: true})
            await fs.cp(stagedPath, destPath, ~options={recursive: false})
            Ok((destPath, backupOpt))
          } catch {
          | JsExn(obj) =>
            let msg = switch JsExn.message(obj) {
            | Some(m) => m
            | None => "Copy failed"
            }
            Error(("Failed to commit " ++ targetPath ++ ": " ++ msg, None))
          }
        }
      }
    }
  })

  let allResults = await Promise.all(workItems->Array.map(fn => fn()))
  let errors = allResults->Array.filterMap(r => switch r { | Error((e, _)) => Some(e) | Ok(_) => None })
  let successful = allResults->Array.filterMap(r => switch r { | Ok(x) => Some(x) | Error(_) => None })
  let partialCommit = successful->Array.map(((path, _)) => path)
  let backups: array<backupEntry> = successful->Array.map(((path, backup)) => (path, backup))->Array.filterMap(((_, backup)) => {
    switch backup {
    | Some(entry) => Some(entry)
    | None => None
    }
  })

  if errors->Array.length > 0 {
    let firstError = errors[0]->Option.getOr("Unknown error")
    let err: phase2Error = {message: firstError}
    switch partialCommit->Array.length {
    | 0 => Error(err)
    | _ => Error({...err, partialCommit: partialCommit})
    }
  } else {
    Ok((partialCommit->Array.length, backups))
  }
}

let rollbackOutput: (
  ~committedFiles: array<string>,
  ~backups: array<backupEntry>,
  ~outputDir: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, array<rollbackFailure>>> = async (
  ~committedFiles,
  ~backups,
  ~outputDir,
  ~path,
  ~fs,
) => {
  let backupByOutput: dict<backupEntry> = Dict.make()
  backups->Array.forEach(backup => backupByOutput->Dict.set(backup.outputPath, backup))

  let workItems = committedFiles->Array.map(outputPath => async () => {
    // Re-validate containment: each outputPath must be within outputDir.
    // Without this check, a future caller could pass unvalidated paths and
    // rm/cp outside the committed output tree during rollback.
    let isWithin = await PathSecurity.isWithinTree(outputPath, outputDir, path, fs)
    if !isWithin {
      Error({path: outputPath, reason: "output path outside output tree during rollback"})
    } else {
      switch backupByOutput->Dict.get(outputPath) {
      | Some(backup) => {
          try {
            await fs.cp(backup.backupPath, outputPath, ~options={recursive: false})
            Ok()
          } catch {
          | JsExn(obj) =>
            let msg = switch JsExn.message(obj) {
            | Some(m) => m
            | None => "unknown error"
            }
            Error({path: outputPath, reason: msg})
          | _ => Error({path: outputPath, reason: "unknown error"})
          }
        }
      | None => {
          try {
            await fs.rm(outputPath, ~options={recursive: false})
            Ok()
          } catch {
          | JsExn(obj) =>
            let msg = switch JsExn.message(obj) {
            | Some(m) => m
            | None => "unknown error"
            }
            Error({path: outputPath, reason: msg})
          | _ => Error({path: outputPath, reason: "unknown error"})
          }
        }
      }
    }
  })

  let results = await Promise.all(workItems->Array.map(fn => fn()))
  let failures = results->Array.filterMap(r =>
    switch r {
    | Error(f) => Some(f)
    | Ok(_) => None
    }
  )

  switch failures->Array.length {
  | 0 => Ok()
  | _ => Error(failures)
  }
}

// Rollback: remove staging directory
// Asserts staging dir is within tmpRoot before rm to prevent catastrophic deletion.
let rollback: (string, ~tmpRoot: string, ~path: Ports.path, ~fs: Ports.fileSystem) => promise<result<unit, string>> = async (stagingDir, ~tmpRoot, ~path, ~fs) => {
  // Guard: staging dir must be within the known tmpdir tree.
  // Without this, a caller passing a path like /usr could wipe system directories.
  let isWithin = await PathSecurity.isWithinTree(stagingDir, tmpRoot, path, fs)
  if !isWithin {
    Error("Refusing to remove staging dir outside temp directory: " ++ stagingDir)
  } else {
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
}
