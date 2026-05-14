type fileHandle

@module("node:fs/promises")
external readFile: (string, ~options: {encoding: string}=?) => promise<string> = "readFile"

@module("node:fs/promises")
external writeFile: (string, string, ~options: {encoding: string}=?) => promise<unit> = "writeFile"

@module("node:fs/promises")
external mkdir: (string, ~options: {recursive: bool}=?) => promise<string> = "mkdir"

@module("node:fs/promises")
external rm: (string, ~options: {recursive: bool}=?) => promise<unit> = "rm"

@module("node:fs/promises")
external cp: (string, string, ~options: {recursive: bool}=?) => promise<unit> = "cp"

@module("node:fs/promises")
external readdir: (string, ~options: {withFileTypes: bool}=?) => promise<array<string>> = "readdir"

@module("node:fs/promises")
external stat: string => promise<{
  isFile: unit => bool,
  isDirectory: unit => bool,
}> = "stat"

@module("node:fs/promises")
external access: (string, ~mode: int=?) => promise<unit> = "access"

@module("node:fs/constants")
let F_OK: int = 0

let fileExists: string => promise<bool> = async path => {
  try {
    await access(path, ~mode=F_OK)
    true
  } catch {
  | _ => false
  }
}