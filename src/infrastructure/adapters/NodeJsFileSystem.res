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
      mtimeMs: ?Some(Obj.magic(s)["mtimeMs"]),
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
  makeStagingDir: async prefix => {
    let tmpPrefix = NodeJs.Path.join(NodeJs.Os.tmpdir(), prefix)
    await NodeJs.Fs.mkdtemp(tmpPrefix)
  },
}
