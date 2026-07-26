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

module TextDecoder = {
  type t
  @new external make: unit => t = "TextDecoder"
  @send external decode: (t, array<int>) => string = "decode"
}

module Signal = {
  @val @scope("Deno") external addSignalListener: (string, unit => unit) => unit = "addSignalListener"
  @val @scope("Deno") external removeSignalListener: (string, unit => unit) => unit = "removeSignalListener"
}

module Fs = {
  type mkdirOptions = {recursive: bool}
  type rmOptions = {recursive: bool}
  
  @val @scope(("Deno", "env")) external envToObject: unit => dict<string> = "toObject"
  
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

  type asyncIterable<'a>

  @val @scope("Deno") external readDir: string => asyncIterable<dirEntry> = "readDir"
  @val @scope("Array") external fromAsync: asyncIterable<'a> => promise<array<'a>> = "fromAsync"

  type notFoundProto

  @val @scope(("Deno", "errors", "NotFound")) external notFoundProto: notFoundProto = "prototype"

  @send external isPrototypeOf: (notFoundProto, 'a) => bool = "isPrototypeOf"

  let isNotFound: 'a => bool = obj => isPrototypeOf(notFoundProto, obj)

  @warning("-27")
  let readDirAsync: string => promise<array<string>> = async path => {
    let entries = await fromAsync(path->readDir)
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
      if isNotFound(obj) { false } else { throw(Not_found) }
    }
  }
  
  @val @scope("Deno") external makeTempDirSync: unit => string = "makeTempDirSync"

  @val @scope("Deno") external makeTempDir: unit => promise<string> = "makeTempDir"

  @val @scope("Deno") external tempDir: unit => string = "tempDir"

  @val @scope("Deno") external realPath: string => promise<string> = "realPath"
}
