open Deno.Fs

// DenoFileSystem — Deno fs adapter implementing Ports.fileSystem.
// KNOWN GAP: readFile, writeFile, cp, and readdir silently discard ~options.
// Deno.readTextFile/writeTextFile handle encoding via string automatically.
// copyFile and readDirAsync do not support recursive or withFileTypes.
// If a caller needs these options, implement them on Deno before relying on them.

let make: unit => Ports.fileSystem = () => {
  readFile: (path, ~options=?) => {
    let _ = options // Deno readTextFile handles encoding via string automatically
    readTextFile(path)
  },
  writeFile: (path, content, ~options=?) => {
    let _ = options
    writeTextFile(path, content)
  },
  mkdir: async (path, ~options=?) => {
    let recursive = switch options {
    | Some(opts) => opts.recursive
    | None => false
    }
    await mkdir(path, {recursive: recursive})
    path
  },
  rm: async (path, ~options=?) => {
    let recursive = switch options {
    | Some(opts) => opts.recursive
    | None => false
    }
    await remove(path, {recursive: recursive})
  },
  cp: async (src, dst, ~options=?) => {
    let _ = options
    await copyFile(src, dst)
  },
  readdir: async (path, ~options=?) => {
    let _ = options
    await readDirAsync(path)
  },
  stat: async path => {
    let s = await stat(path)
    let isDir = s.isDirectory
    let isF = s.isFile
    let res: Ports.statResult = {
      isDirectory: () => isDir,
      isFile: () => isF,
    }
    res
  },
  fileExists: fileExists,
  realpath: Deno.Fs.realPath,
  makeStagingDir: async _prefix => {
    let ts = Date.now()->Float.toInt->Int.toString
    let r = Math.random()->Float.toString
    let r2 = String.split(r, ".")->Array.get(1)->Option.getOr("x")
    let dir = "blueprint-" ++ ts ++ "-" ++ r2
    let tmp = Deno.Fs.tempDir()
    let fullPath = Path.join(tmp, dir)
    try {
      let _ = await Deno.Fs.mkdir(fullPath, {recursive: true})
      fullPath
    } catch {
    | _ => fullPath
    }
  },
}
