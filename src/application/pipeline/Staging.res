// Staging: Phase1 staging-dir lifecycle (create, write staged file, remove on failure).
// No imports of other phase sub-modules — sits below Phase1 in the dependency arrow.

let create: (~tmpDir: string, ~fs: Ports.fileSystem) => promise<result<string, string>> = async (
  ~tmpDir,
  ~fs,
) => {
  try {
    let _ = await fs.mkdir(tmpDir, ~options={recursive: true})
    Ok(tmpDir)
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "mkdir failed"
    }
    Error(msg)
  }
}

let writeStagedFile: (
  ~stagingDir: string,
  ~targetPath: string,
  ~renderedBody: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, string>> = async (
  ~stagingDir,
  ~targetPath,
  ~renderedBody,
  ~path,
  ~fs,
) => {
  let stagedPath = path.join(stagingDir, targetPath)
  // Self-contained containment check: reject paths that escape the staging dir.
  // This guards against a future caller passing an unvalidated traversal path.
  let isWithin = await PathSecurity.isWithinTree(stagedPath, stagingDir, path, fs)
  if !isWithin {
    Error("Staged path escapes staging directory: " ++ targetPath)
  } else {
    let stagedDir = path.dirname(stagedPath)
    try {
      let _ = await fs.mkdir(stagedDir, ~options={recursive: true})
      let _ = await fs.writeFile(stagedPath, renderedBody)
      Ok()
    } catch {
    | JsExn(obj) =>
      let msg = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Write failed"
      }
      Error(msg)
    }
  }
}

let removeStagingDir: (string, ~fs: Ports.fileSystem) => promise<unit> = async (
  stagingDir,
  ~fs,
) => {
  try {
    let _ = await fs.rm(stagingDir, ~options={recursive: true})
  } catch {
  | _ => ()
  }
  ()
}