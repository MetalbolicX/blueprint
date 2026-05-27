/**
 * PathSecurity — path traversal protection
 * Provides utilities for validating paths are within allowed directory trees
 */

// Attempt to resolve realpath, falling back to the resolved path if it fails
// (e.g., when the path doesn't exist yet — common for new files)
let _resolveRealPath: (string, Ports.fileSystem) => promise<string> = async (path, fs) => {
  try {
    await fs.realpath(path)
  } catch {
  | _ => path
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
  // If realpath fails (path doesn't exist), fall back to the resolved path.
  let resolvedPathP = _resolveRealPath(realResolvedPath, fs)
  let resolvedRootP = _resolveRealPath(realResolvedRoot, fs)

  let both: promise<array<string>> = Promise.all([resolvedPathP, resolvedRootP])
  both->Promise.then(arr => {
    let resolvedPath = arr[0]->Option.getOr(realResolvedPath)
    let resolvedRoot = arr[1]->Option.getOr(realResolvedRoot)
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

    Promise.resolve(isBoundary(resolvedPath, resolvedRoot))
  })
}