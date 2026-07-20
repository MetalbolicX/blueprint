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
    (s :> Ports.statResult)
  },
  fileExists: NodeJs.Fs.fileExists,
  realpath: realpath,
}