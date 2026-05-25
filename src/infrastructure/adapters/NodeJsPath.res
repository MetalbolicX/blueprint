/**
 * NodeJsPath — Node.js path adapter implementing Ports.path.
 */

open NodeJs

let make: unit => Ports.path = () => {
  join: Path.join,
  resolve: Path.resolve,
  dirname: Path.dirname,
  isAbsolute: Path.isAbsolute,
  basename: (path, ~ext=?) => Path.basename(path, ~ext=?ext),
}