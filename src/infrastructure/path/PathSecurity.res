/**
 * PathSecurity — path traversal protection
 * Provides utilities for validating paths are within allowed directory trees
 */

let isWithinTree: (string, string, Ports.path) => bool = (path, root, pathAdapter) => {
  let resolvedPath = pathAdapter.resolve(path, "")
  let resolvedRoot = pathAdapter.resolve(root, "")
  
  // Since we don't have sep in ports yet, we can use string lengths and slash checks.
  // Wait, or we can use replace regex for backslashes to forward slashes?
  // Let's just use string startsWith and check boundary.
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

  isBoundary(resolvedPath, resolvedRoot)
}