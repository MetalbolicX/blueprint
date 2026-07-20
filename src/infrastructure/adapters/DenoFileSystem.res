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
}
