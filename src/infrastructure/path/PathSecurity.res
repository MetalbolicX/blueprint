/**
 * PathSecurity — path traversal protection
 * Provides utilities for validating paths are within allowed directory trees
 */

let isWithinTree: (string, string) => bool = (path, root) => {
  let resolvedPath = Bindings.NodeJs.Path.resolve(path, "")
  let resolvedRoot = Bindings.NodeJs.Path.resolve(root, "")
  let separator = Bindings.NodeJs.Path.sep

  // resolvedPath must start with resolvedRoot + separator
  // Use string comparison after ensuring proper prefix
  // Handle exact match case (path equals root)
  resolvedPath == resolvedRoot || String.startsWith(resolvedPath, resolvedRoot ++ separator)
}