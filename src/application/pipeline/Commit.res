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
  backups?: array<backupEntry>,
  failedTargets?: array<string>,
  failedBackups?: array<backupEntry>,
  createdDirs?: array<string>,
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
    // Step 5: refuse to back up (and thus overwrite) a symbolic-link destination.
    // The lstat is inside the try so a transient fs error surfaces as a backup
    // Error rather than an unhandled rejection; a genuine symlink returns Error.
    let backupPath = path.join(stagingDir, path.join(backupDirName, targetPath))
    let backupDir = path.dirname(backupPath)
    try {
      let destStat = await fs.lstat(destPath)
      if destStat.isSymbolicLink() {
        Error("Refusing to back up symbolic link: " ++ destPath)
      } else {
        let _ = await fs.mkdir(backupDir, ~options={recursive: true})
        await fs.cp(destPath, backupPath, ~options={recursive: false})
        Ok(Some({outputPath: destPath, backupPath}))
      }
    } catch {
    | JsExn(obj) =>
      let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="Backup failed")
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
  ~pathSecurity: Ports.pathSecurity,
  ~onCommitting: (string, option<backupEntry>) => unit=?,
  ~onCreatedDirs: array<string> => unit=?,
) => promise<result<(int, array<backupEntry>, array<string>), phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
  ~fs,
  ~path,
  ~pathSecurity,
  ~onCommitting=?,
  ~onCreatedDirs=?,
) => {
  let seenTargets: ref<dict<string>> = ref(Dict.make())
  let createdDirs: ref<array<string>> = ref([])
  let checkedDirs: ref<dict<string>> = ref(Dict.make())
  let outputRoot = path.resolve(outputDir, ".")
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

    let isWithin = await pathSecurity.isWithinTree(destPath, outputDir, path, fs)
    if !isWithin {
      Error(("Target path outside output tree: " ++ targetPath, None, None))
    } else {
      let rec probeDir: string => promise<result<unit, string>> = async dir => {
        if path.resolve(dir, ".") == outputRoot || checkedDirs.contents->Dict.has(dir) {
          Ok()
        } else {
          try {
            let _ = await fs.stat(dir)
            checkedDirs.contents->Dict.set(dir, dir)->ignore
            Ok()
          } catch {
          | JsExn(obj) =>
            let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="Directory probe failed")
            if String.includes(msg, "ENOENT") {
              checkedDirs.contents->Dict.set(dir, dir)->ignore
              if !(createdDirs.contents->Array.some(item => item == dir)) {
                createdDirs.contents->Array.push(dir)->ignore
                switch onCreatedDirs {
                | Some(callback) => callback(createdDirs.contents->Array.map(item => item))
                | None => ()
                }
              }
              let parent = path.dirname(dir)
              if parent == dir {
                Ok()
              } else {
                await probeDir(parent)
              }
            } else {
              Error(msg)
            }
          | _ => Error("Directory probe failed")
          }
        }
      }
      switch await probeDir(destDir) {
      | Error(message) => Error(("Failed to inspect output directory for " ++ targetPath ++ ": " ++ message, None, None))
      | Ok() => {
          switch await backupIfOverwriting(~targetPath, ~outputDir, ~stagingDir, ~fs, ~path) {
          | Error(e) => Error((e, None, None))
          | Ok(backupOpt) => {
          switch onCommitting {
          | Some(callback) => callback(destPath, backupOpt)
          | None => ()
          }
          // Step 5: refuse to copy a symbolic-link staged file into the output tree.
          // The lstat is inside the try so a missing/unreadable staged file surfaces
          // as a commit Error (preserving partialCommit) rather than an unhandled
          // rejection; a genuine symlink returns Error without ever reaching cp.
          try {
            let stagedStat = await fs.lstat(stagedPath)
            if stagedStat.isSymbolicLink() {
              Error(("Refusing to copy symbolic link: " ++ stagedPath, backupOpt, Some(destPath)))
            } else {
              let _ = await fs.mkdir(destDir, ~options={recursive: true})
              await fs.cp(stagedPath, destPath, ~options={recursive: false})
              await EngineLifecycle.touchHeartbeat(~fs, ~stagingDir, ~path)
              Ok((destPath, backupOpt))
            }
          } catch {
          | JsExn(obj) =>
            let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="Copy failed")
            Error(("Failed to commit " ++ targetPath ++ ": " ++ msg, backupOpt, Some(destPath)))
          }
          }
          }
        }
      }
    }
  })

  let allResults = await Promise.all(workItems->Array.map(fn => fn()))
  let errors = allResults->Array.filterMap(r => switch r { | Error((e, _, _)) => Some(e) | Ok(_) => None })
  let failed = allResults->Array.filterMap(r => switch r { | Error((_, backup, target)) => target->Option.map(t => (t, backup)) | Ok(_) => None })
  let failedTargets = failed->Array.map(((target, _)) => target)
  let failedBackups = failed->Array.filterMap(((_, backup)) => backup)
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
    let err: phase2Error = {
      message: firstError,
      partialCommit: ?(partialCommit->Array.length > 0 ? Some(partialCommit) : None),
      backups: ?(backups->Array.length > 0 ? Some(backups) : None),
      failedTargets: ?(failedTargets->Array.length > 0 ? Some(failedTargets) : None),
      failedBackups: ?(failedBackups->Array.length > 0 ? Some(failedBackups) : None),
      createdDirs: ?(createdDirs.contents->Array.length > 0 ? Some(createdDirs.contents) : None),
    }
    Error(err)
  } else {
    Ok((partialCommit->Array.length, backups, createdDirs.contents))
  }
}

let rollbackOutput: (
  ~committedFiles: array<string>,
  ~backups: array<backupEntry>,
  ~createdDirs: array<string>=?,
  ~outputDir: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
  ~pathSecurity: Ports.pathSecurity,
) => promise<result<unit, array<rollbackFailure>>> = async (
  ~committedFiles,
  ~backups,
  ~createdDirs=?,
  ~outputDir,
  ~path,
  ~fs,
  ~pathSecurity,
) => {
  let createdDirs = createdDirs->Option.getOr([])
  let backupByOutput: dict<backupEntry> = Dict.make()
  backups->Array.forEach(backup => backupByOutput->Dict.set(backup.outputPath, backup))

  let workItems = committedFiles->Array.map(outputPath => async () => {
    // Re-validate containment: each outputPath must be within outputDir.
    // Without this check, a future caller could pass unvalidated paths and
    // rm/cp outside the committed output tree during rollback.
    let isWithin = await pathSecurity.isWithinTree(outputPath, outputDir, path, fs)
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
            let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="unknown error")
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
            let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="unknown error")
            if String.includes(msg, "ENOENT") {
              Ok()
            } else {
              Error({path: outputPath, reason: msg})
            }
          | _ => Error({path: outputPath, reason: "unknown error"})
          }
        }
      }
    }
  })

  let results = await Promise.all(workItems->Array.map(fn => fn()))
  let fileFailures = results->Array.filterMap(r =>
    switch r {
    | Error(f) => Some(f)
    | Ok(_) => None
    }
  )
  let sortedDirs = createdDirs->Array.map(dir => dir)
  sortedDirs->Array.sort((left, right) =>
    Int.toFloat(String.split(right, "/")->Array.length - String.split(left, "/")->Array.length)
  )
  let dirFailures: ref<array<rollbackFailure>> = ref([])
  let rec removeDir: int => promise<unit> = async index => {
    switch Array.get(sortedDirs, index) {
    | None => ()
    | Some(dir) => {
        let isWithin = await pathSecurity.isWithinTree(dir, outputDir, path, fs)
        if !isWithin {
          dirFailures.contents->Array.push({path: dir, reason: "output path outside output tree during rollback"})->ignore
        } else {
          try {
            let entries = await fs.readdir(dir)
            if entries->Array.length == 0 {
              try {
                await fs.rm(dir, ~options={recursive: true})
              } catch {
              | JsExn(obj) =>
                let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="unknown error")
                if !(String.includes(msg, "ENOENT")) {
                  dirFailures.contents->Array.push({path: dir, reason: msg})->ignore
                }
              | _ => dirFailures.contents->Array.push({path: dir, reason: "unknown error"})->ignore
              }
            }
          } catch {
          | JsExn(obj) =>
            let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="unknown error")
            if !(String.includes(msg, "ENOENT")) {
              dirFailures.contents->Array.push({path: dir, reason: msg})->ignore
            }
          | _ => dirFailures.contents->Array.push({path: dir, reason: "unknown error"})->ignore
          }
        }
        await removeDir(index + 1)
      }
    }
  }
  await removeDir(0)
  let failures = fileFailures->Array.concat(dirFailures.contents)

  switch failures->Array.length {
  | 0 => Ok()
  | _ => Error(failures)
  }
}

// Rollback: remove staging directory
// Asserts staging dir is within tmpRoot before rm to prevent catastrophic deletion.
let rollback: (string, ~tmpRoot: string, ~path: Ports.path, ~pathSecurity: Ports.pathSecurity, ~fs: Ports.fileSystem) => promise<result<unit, string>> = async (stagingDir, ~tmpRoot, ~path, ~pathSecurity, ~fs) => {
  // Guard: staging dir must be within the known tmpdir tree.
  // Without this, a caller passing a path like /usr could wipe system directories.
  let isWithin = await pathSecurity.isWithinTree(stagingDir, tmpRoot, path, fs)
  if !isWithin {
    Error("Refusing to remove staging dir outside temp directory: " ++ stagingDir)
  } else {
    try {
      await fs.rm(stagingDir, ~options={recursive: true})
      Ok()
    } catch {
    | JsExn(obj) =>
      let msg = Errors.extractErrorMessage(JsExn(obj), ~fallback="Failed to remove staging directory")
      Error(msg)
    }
  }
}
