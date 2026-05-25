// Deno global API bindings

module Fs = {
  type mkdirOptions = {recursive: bool}
  type rmOptions = {recursive: bool}
  
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
  
  // Deno.readDir returns an async iterable, we'll need a helper to collect it
  // For now, let's use a raw helper for readDir to return array<string>
  let readDirAsync: string => promise<array<string>> = %raw(`
    async (path) => {
      const entries = [];
      for await (const entry of Deno.readDir(path)) {
        entries.push(entry.name);
      }
      return entries;
    }
  `)
  
  type fileInfo = {
    isFile: bool,
    isDirectory: bool,
    isSymlink: bool,
    size: int,
    mtime: Nullable.t<Date.t>,
  }
  
  @val @scope("Deno") external stat: string => promise<fileInfo> = "stat"
  
  // helper to check if file exists (Deno usually uses try/catch on stat)
  let fileExists: string => promise<bool> = %raw(`
    async (path) => {
      try {
        await Deno.stat(path);
        return true;
      } catch (e) {
        if (e instanceof Deno.errors.NotFound) {
          return false;
        }
        throw e;
      }
    }
  `)
  
  @val @scope("Deno") external makeTempDirSync: unit => string = "makeTempDirSync"
}
