/**
 * Node.js os bindings — operating system utilities
 */

@module("node:os")
external tmpdir: unit => string = "tmpdir"

@module("node:os")
external homedir: unit => string = "homedir"

let makeStagingDir: unit => string = () => {
  let ts = Date.now()->Float.toInt->Int.toString
  let r = Math.random()->Float.toString
  let r2 = String.split(r, ".")->Array.get(1)->Option.getOr("x")
  let dir = "blueprint-" ++ ts ++ "-" ++ r2
  let tmp = tmpdir()
  let fullPath = Path.join(tmp, dir)
  // Ensure directory exists using sync API
  try {
    let _ = Fs.mkdirSync(fullPath, ~options={recursive: true})
    fullPath
  } catch {
  | _ => fullPath  // If mkdirSync fails, return path anyway
  }
}
