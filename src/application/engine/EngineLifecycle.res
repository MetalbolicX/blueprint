// EngineLifecycle.res


let stagingDirPrefix = "blueprint-"
let backupDirName = ".blueprint-backup"
let staleThresholdMs = 5 * 60 * 1000

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
      let probeDir = fs.makeStagingDir()
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
  let cleanupOps = tmpEntries->Array.map(async entry => {
      if String.startsWith(entry, stagingDirPrefix) {
        switch parseStagingDirTimestamp(entry) {
        | Some(createdAt) if nowMs - createdAt >= staleThresholdMs => {
            let fullPath = path.join(resolvedTmpRoot, entry)
            try {
              let stat = await fs.stat(fullPath)
              if stat.isDirectory() {
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
    await cleanupPath(~target=backupDir, ~fs)
  }
}

let registerSignalHandlers: (~process: Ports.process, ~stagingDirRef: ref<option<string>>, ~fs: Ports.fileSystem) => unit = (
  ~process,
  ~stagingDirRef,
  ~fs,
) => {
  let handleSignal = () => {
    let cleanupPromise = switch stagingDirRef.contents {
    | Some(stagingDir) => {
        stagingDirRef.contents = None
        cleanupPath(~target=stagingDir, ~fs)
      }
    | None => Promise.resolve()
    }

    cleanupPromise
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
