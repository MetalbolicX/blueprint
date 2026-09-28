/**
 * NodeJsFileSystem — Node.js fs + os adapter implementing Ports.fileSystem.
 */

open NodeJs.Fs

@module("node:fs") @scope("promises")
external realpath: string => promise<string> = "realpath"

let make: unit => Ports.fileSystem = () => {
  readFile: (path, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.Fs.readFileOptions))
    | None => None
    }
    readFile(path, ~options=?opts)
  },
  writeFile: (path, content, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.Fs.writeFileOptions))
    | None => None
    }
    writeFile(path, content, ~options=?opts)
  },
  mkdir: (path, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.Fs.mkdirOptions))
    | None => None
    }
    mkdir(path, ~options=?opts)
  },
  rm: (path, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.Fs.rmOptions))
    | None => None
    }
    rm(path, ~options=?opts)
  },
  cp: (src, dst, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.Fs.cpOptions))
    | None => None
    }
    cp(src, dst, ~options=?opts)
  },
  readdir: (path, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.Fs.readdirOptions))
    | None => None
    }
    readdir(path, ~options=?opts)
  },
  stat: async path => {
    let s = await NodeJs.Fs.stat(path)
    let isDir = s.isDirectory()
    let isF = s.isFile()
    let res: Ports.statResult = {
      isDirectory: () => isDir,
      isFile: () => isF,
    }
    res
  },
  lstat: async path => {
    let s = await NodeJs.Fs.lstat(path)
    let isDir = s.isDirectory()
    let isF = s.isFile()
    // isSymbolicLink is on Node.js Stats but not in our thin binding type;
    // use Obj.magic to read it since we know Node's lstat result always has it.
    let isSym: bool = Obj.magic(s)["isSymbolicLink"]()
    let res: Ports.lstatResult = {
      isDirectory: () => isDir,
      isFile: () => isF,
      isSymbolicLink: () => isSym,
    }
    res
  },
  fileExists: NodeJs.Fs.fileExists,
  realpath: realpath,
  makeStagingDir: async _prefix => {
    let ts = Date.now()->Float.toInt->Int.toString
    let r = Math.random()->Float.toString
    let r2 = String.split(r, ".")->Array.get(1)->Option.getOr("x")
    let dir = "blueprint-" ++ ts ++ "-" ++ r2
    let tmp = NodeJs.Os.tmpdir()
    let fullPath = NodeJs.Path.join(tmp, dir)
    try {
      let _ = await NodeJs.Fs.mkdir(fullPath, ~options={recursive: true})
      fullPath
    } catch {
    | _ => fullPath
    }
  },
}
