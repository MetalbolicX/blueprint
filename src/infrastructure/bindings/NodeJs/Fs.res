/**
 * Node.js fs bindings — file system operations
 */

type fileHandle

type readFileOptions = {encoding: string}
type writeFileOptions = {encoding: string}
type mkdirOptions = {recursive: bool}
type rmOptions = {recursive: bool}
type cpOptions = {recursive: bool}
type readdirOptions = {withFileTypes: bool}
type statResult = {
  isFile: unit => bool,
  isDirectory: unit => bool,
}
type accessOptions = {mode: int}

@module("node:fs") @scope("promises")
external readFile: (string, ~options: readFileOptions=?) => promise<string> = "readFile"

@module("node:fs") @scope("promises")
external writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit> = "writeFile"

@module("node:fs") @scope("promises")
external mkdir: (string, ~options: mkdirOptions=?) => promise<string> = "mkdir"

@module("node:fs") @scope("promises")
external rm: (string, ~options: rmOptions=?) => promise<unit> = "rm"

@module("node:fs") @scope("promises")
external cp: (string, string, ~options: cpOptions=?) => promise<unit> = "cp"

@module("node:fs") @scope("promises")
external readdir: (string, ~options: readdirOptions=?) => promise<array<string>> = "readdir"

@module("node:fs") @scope("promises")
external stat: string => promise<statResult> = "stat"

@module("node:fs") @scope("promises")
external access: (string, ~mode: int=?) => promise<unit> = "access"

// Sync mkdir for internal use
@module("node:fs")
external mkdirSync: (string, ~options: mkdirOptions=?) => string = "mkdirSync"

let fOk = 0

let fileExists: string => promise<bool> = async path => {
  try {
    await access(path, ~mode=fOk)
    true
  } catch {
  | _ => false
  }
}
