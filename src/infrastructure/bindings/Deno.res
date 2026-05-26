// Deno global API bindings

module Command = {
  type options = {
    args?: array<string>,
    cwd?: string,
    env?: dict<string>,
    stdout?: string,
    stderr?: string,
    timeout?: int,
  }

  type output = {
    code: int,
    stdout: array<int>,
    stderr: array<int>,
    signal: Nullable.t<string>,
  }

  type t

  @new
  external make: (string, options) => t = "Deno.Command"

  @send
  external output: t => promise<output> = "output"
}

module Fs = {
  type mkdirOptions = {recursive: bool}
  type rmOptions = {recursive: bool}
  
  @val @scope("Deno.env") external envToObject: unit => dict<string> = "toObject"
  
  @val @scope("Deno") external readTextFile: string => promise<string> = "readTextFile"
  @val @scope("Deno") external writeTextFile: (string, string) => promise<unit> = "writeTextFile"
  @val @scope("Deno") external mkdir: (string, mkdirOptions) => promise<unit> = "mkdir"
  @val @scope("Deno") external remove: (string, rmOptions) => promise<unit> = "remove"
  @val @scope("Deno") external copyFile: (string, string) => promise<unit> = "copyFile"
  
  type dirEntry = {
    name: string,
    isFile: bool,
    isDirectory: bool,
    isSymlink: bool,
  }
  
  @val @scope("Deno") external readDir: string => promise<array<dirEntry>> = "readDir"

  let readDirAsync: string => promise<array<string>> = async path => {
    let entries = await readDir(path)
    entries->Array.map(entry => entry.name)
  }
  
  type fileInfo = {
    isFile: bool,
    isDirectory: bool,
    isSymlink: bool,
    size: int,
    mtime: Nullable.t<Date.t>,
  }
  
@val @scope("Deno") external stat: string => promise<fileInfo> = "stat"

  /**
   * Checks if a file exists at the given path.
   * Returns false for Deno.errors.NotFound, re-raises all other exceptions
   * as ReScript Not_found so callers must handle unexpected errors.
   */
  let fileExists: string => promise<bool> = async path => {
    try {
      let _ = await stat(path)
      true
    } catch {
    | JsExn(obj) =>
      let isNotFound: bool = %raw("(e) => e instanceof Deno.errors.NotFound")(obj)
      if isNotFound { false } else { throw(Not_found) }
    }
  }
  
  @val @scope("Deno") external makeTempDirSync: unit => string = "makeTempDirSync"
}
