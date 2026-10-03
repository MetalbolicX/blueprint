open Ports

let make: unit => pathSecurity = () => {
  isWithinTree: (path, root, pathAdapter, fs) =>
    PathSecurity.isWithinTree(path, root, pathAdapter, fs),
}
