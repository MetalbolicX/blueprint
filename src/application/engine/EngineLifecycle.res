// EngineLifecycle.res


let stagingDirPrefix = "blueprint-"
let backupDirName = ".blueprint-backup"
let staleThresholdMs = 30 * 60 * 1000
let recentMtimeThresholdMs = 15 * 60 * 1000
let heartbeatName = ".blueprint-heartbeat"

let touchHeartbeat: (~fs: Ports.fileSystem, ~stagingDir: string, ~path: Ports.path) => promise<unit> = async (~fs, ~stagingDir, ~path) => {
  try {
    await fs.writeFile(path.join(stagingDir, heartbeatName), "")
  } catch {
  | _ => ()
  }
}

let cleanupPath: (~target: string, ~fs: Ports.fileSystem) => promise<unit> = async (~target, ~fs) => {
  try {
    let _ = await fs.rm(target, ~options={recursive: true})
    ()
  } catch {
  | _ => ()
  }
}

let parseStagingDirTimestamp = (dirName: string): option<int> => {
  let parts = String.split(dirName, "-")
  switch Array.get(parts, 1) {
  | Some("") =>
    switch Array.get(parts, 2) {
    | Some(rawTs) => Int.fromString("-" ++ rawTs)
    | None => None
    }
  | Some(rawTs) => Int.fromString(rawTs)
  | None => None
  }
}

let cleanupOrphans: (~outputDir: string, ~fs: Ports.fileSystem, ~path: Ports.path, ~tmpRoot: string=?) => promise<unit> = async (
  ~outputDir,
  ~fs,
  ~path,
  ~tmpRoot=?,
) => {
  let resolvedTmpRoot = switch tmpRoot {
  | Some(dir) => dir
  | None => {
      let probeDir = await fs.makeStagingDir(stagingDirPrefix ++ "tmp-root-probe")
      let probeRoot = path.dirname(probeDir)
      await cleanupPath(~target=probeDir, ~fs)
      probeRoot
    }
  }

  let tmpEntries = try {
    await fs.readdir(resolvedTmpRoot)
  } catch {
  | _ => []
  }

  let nowMs = Date.now()->Float.toInt
  let nowMsFloat = Date.now()
  let cleanupOps = tmpEntries->Array.map(async entry => {
      if String.startsWith(entry, stagingDirPrefix) {
        switch parseStagingDirTimestamp(entry) {
        | Some(createdAt) if nowMs - createdAt >= staleThresholdMs => {
            let fullPath = path.join(resolvedTmpRoot, entry)
            try {
              let stat = await fs.stat(fullPath)
              let oldEnoughByMtime = switch stat.mtimeMs {
              | Some(mtimeMs) => nowMsFloat -. mtimeMs >= recentMtimeThresholdMs->Int.toFloat
              | None => false
              }
              let heartbeatOldOrMissing = if oldEnoughByMtime {
                try {
                  let heartbeatStat = await fs.stat(path.join(fullPath, heartbeatName))
                  switch heartbeatStat.mtimeMs {
                  | Some(mtimeMs) => nowMsFloat -. mtimeMs >= recentMtimeThresholdMs->Int.toFloat
                  | None => false
                  }
                } catch {
                | JsExn(obj) => {
                    let message = Errors.extractErrorMessage(JsExn(obj), ~fallback="Heartbeat stat failed")
                    String.includes(message, "ENOENT")
                  }
                | _ => false
                }
              } else {
                false
              }
              if stat.isDirectory() && oldEnoughByMtime && heartbeatOldOrMissing {
                await cleanupPath(~target=fullPath, ~fs)
              }
            } catch {
            | _ => ()
            }
          }
        | _ => ()
        }
      }
    })

  let _ = await Promise.all(cleanupOps)

  let backupDir = path.join(outputDir, backupDirName)
  let backupExists = try {
    await fs.fileExists(backupDir)
  } catch {
  | _ => false
  }

  if backupExists {
    Console.warn("Removing legacy backup dir: " ++ backupDir)
    await cleanupPath(~target=backupDir, ~fs)
  }
}

let registerSignalHandlers: (~process: Ports.process, ~stagingDirRef: ref<option<string>>, ~commitRollbackRef: ref<option<unit => promise<unit>>>, ~fs: Ports.fileSystem) => unit = (
  ~process,
  ~stagingDirRef,
  ~commitRollbackRef,
  ~fs,
) => {
  let handleSignal = () => {
    let rollbackPromise = switch commitRollbackRef.contents {
    | Some(rollback) => rollback()
    | None => Promise.resolve()
    }

    rollbackPromise->Promise.then(_ => {
      let cleanupPromise = switch stagingDirRef.contents {
      | Some(stagingDir) => {
          stagingDirRef.contents = None
          cleanupPath(~target=stagingDir, ~fs)
        }
      | None => Promise.resolve()
      }
      cleanupPromise
    })
    ->Promise.then(_ => {
      process.exit(1)
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      process.exit(1)
      Promise.resolve()
    })
    ->ignore
  }

  process.onSignal("SIGINT", handleSignal)
  process.onSignal("SIGTERM", handleSignal)
}
