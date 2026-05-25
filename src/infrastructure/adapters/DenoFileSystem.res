open Deno.Fs

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
  makeStagingDir: makeTempDirSync,
}
