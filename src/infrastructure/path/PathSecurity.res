/**
 * PathSecurity — path traversal protection
 * Provides utilities for validating paths are within allowed directory trees
 */

// Attempt to resolve realpath.
// Returns Ok(path) if realpath succeeds OR if it fails with ENOENT/ENOTDIR
// (file doesn't exist yet — correct to fall back).
// Returns Error(msg) for any other failure (EACCES, ELOOP, etc.) so the
// caller can deny rather than silently bypass the symlink check.
let _resolveRealPath: (string, Ports.fileSystem, Ports.path) => promise<result<string, string>> = async (path, fs, pathAdapter) => {
  try {
    let resolved = await fs.realpath(path)
    Ok(resolved)
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "unknown error"
    }
    let code = switch Obj.magic(obj)["code"] {
    | Some(c) => c
    | None => ""
    }
    if code == "ENOENT" || code == "ENOTDIR" {
      let rec walk = async (candidate, tail) => {
        try {
          let resolved = await fs.realpath(candidate)
          Ok(Array.reduce(tail, resolved, (base, component) => pathAdapter.join(base, component)))
        } catch {
        | JsExn(parentErr) =>
          let parentCode = Obj.magic(parentErr)["code"]->Option.getOr("")
          if parentCode == "ENOENT" || parentCode == "ENOTDIR" {
            let parent = pathAdapter.dirname(candidate)
            if parent == candidate {
              Ok(path)
            } else {
              await walk(parent, [pathAdapter.basename(candidate), ...tail])
            }
          } else {
            Error("realpath failed for " ++ candidate ++ ": " ++ JsExn.message(parentErr)->Option.getOr("unknown error") ++ " (code: " ++ parentCode ++ ")")
          }
        | _ => Error("realpath failed for " ++ candidate ++ ": unknown exception")
        }
      }
      await walk(path, [])
    } else {
      Error("realpath failed for " ++ path ++ ": " ++ msg ++ " (code: " ++ code ++ ")")
    }
  | _ => Error("realpath failed for " ++ path ++ ": unknown exception")
  }
}

let isWithinTree: (string, string, Ports.path, Ports.fileSystem) => promise<bool> = (
  path,
  root,
  pathAdapter,
  fs,
) => {
  let realResolvedPath = pathAdapter.resolve(path, "")
  let realResolvedRoot = pathAdapter.resolve(root, "")

  // Resolve symlinks to prevent symlink-based path traversal bypasses.
  // A symlink like /project/link -> /etc would resolve to /etc, which
  // would correctly fail the prefix check below.
  // If realpath fails with ENOENT/ENOTDIR (path doesn't exist yet),
  // fall back to the resolved path. Any other error (EACCES, ELOOP, etc.)
  // is a hard denial — deny rather than silently bypass containment.
  let resolvedPathP = _resolveRealPath(realResolvedPath, fs, pathAdapter)
  let resolvedRootP = _resolveRealPath(realResolvedRoot, fs, pathAdapter)

  resolvedPathP->Promise.then(resolvedPath => {
    switch resolvedPath {
    | Error(_) => Promise.resolve(false)
    | Ok(rp) =>
      resolvedRootP->Promise.then(resolvedRoot => {
        switch resolvedRoot {
        | Error(_) => Promise.resolve(false)
        | Ok(rr) =>
          let isBoundary = (pathStr, rootStr) => {
            let rootLen = String.length(rootStr)
            if pathStr == rootStr {
              true
            } else if String.startsWith(pathStr, rootStr) {
              // Must be a directory boundary. The next char must be / or \
              let nextChar = String.charAt(pathStr, rootLen)
              nextChar == "/" || nextChar == "\\"
            } else {
              false
            }
          }
          Promise.resolve(isBoundary(rp, rr))
        }
      })
    }
  })
}
