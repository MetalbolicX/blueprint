/**
 * Centralized typed bindings to Node.js runtime APIs.
 *
 * Each module groups related bindings from a built-in Node module.
 */

module Fs = {
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
}

module Path = {
  @module("node:path")
  external join: (string, string) => string = "join"

  @module("node:path")
  external resolve: (string, string) => string = "resolve"

  @module("node:path")
  external dirname: string => string = "dirname"

  @module("node:path")
  external basename: (string, ~ext: string=?) => string = "basename"

  @module("node:path")
  external isAbsolute: string => bool = "isAbsolute"
}

module Os = {
  @module("node:os")
  external tmpdir: unit => string = "tmpdir"

  @module("node:os")
  external homedir: unit => string = "homedir"

  let makeStagingDir: unit => string = () => {
    let ts = Date.now()->Float.toInt->Int.toString
    let r = Math.random()->Float.toString
    let r2 = String.split(r, ".")->Array.get(1)->Option.getOr("x")
    let dir = "blueprint-" ++ ts ++ "-" ++ r2
    let tmp = tmpdir()
    let fullPath = Path.join(tmp, dir)
    // Ensure directory exists using sync API
    try {
      let _ = Fs.mkdirSync(fullPath, ~options={recursive: true})
      fullPath
    } catch {
    | _ => fullPath  // If mkdirSync fails, return path anyway
    }
  }
}

module ChildProcess = {
  type childProcess = {
    pid: int,
    stdout: unit,
    stderr: unit,
    status?: int,
    signal?: string,
  }

  type execResult = {stdout: string, stderr: string, status: option<int>, signalCode: option<string>, killed: bool}

  type execOptions = {
    cwd?: string,
    env?: dict<string>,
    shell?: bool,
    encoding?: string,
    timeout?: int,
  }

  // Callback-based exec for proper async handling
  // The callback receives (error, stdout, stderr)
  type execCallback = (Nullable.t<JsExn.t>, string, string) => unit

  @module("node:child_process")
  external execWithCallback: (
    string,
    ~options: execOptions=?,
    ~callback: execCallback,
  ) => childProcess = "exec"

  // Typed view of Node.js child_process error fields.
  // Node.js errors carry fields ReScript's JsExn.t doesn't expose:
  //   - signal: string | null (SIGTERM, SIGKILL, etc.)
  //   - killed: boolean (process was killed by timeout)
  //   - code: number (exit code, defaults to 1)
  // We type the view via a record with `Nullable.t` fields so reading the
  // optional JS properties is explicit. The single cast from JsExn.t lives
  // at the helper boundary below.
  type execError = {
    signal: Nullable.t<string>,
    killed: Nullable.t<bool>,
    code: Nullable.t<int>,
  }

  // Extract Node.js error properties (signal, killed) from Js.Exn.t.
  // Returns tuple: (signalCode, killed)
  let extractExecError: JsExn.t => (option<string>, bool) = e => {
    let err: execError = Obj.magic(e)
    (Nullable.toOption(err.signal), Nullable.toOption(err.killed)->Option.getOr(false))
  }

  // Extract exit code from Node.js error, defaulting to 1.
  // Node.js error.code is the exit code; if missing/undefined, assume 1.
  let extractExitCode: JsExn.t => int = e => {
    let err: execError = Obj.magic(e)
    Nullable.toOption(err.code)->Option.getOr(1)
  }

  // Properly typed async exec using callback API internally
  let execAsync: (
    string,
    ~options: execOptions=?,
  ) => promise<execResult> = (cmd, ~options=?) => {
    Promise.make((resolve, _reject) => {
      let opts = switch options {
      | Some(o) => o
      | None => {}
      }
      let _ = execWithCallback(cmd, ~options=opts, ~callback=(err, stdout, stderr) => {
        if Nullable.isNullable(err) {
          resolve({
            stdout,
            stderr,
            status: Some(0),
            signalCode: None,
            killed: false,
          })
        } else {
          let errObj = Nullable.toOption(err)->Option.getOrThrow
          let (signal, killed) = extractExecError(errObj)
          let code = extractExitCode(errObj)
          resolve({
            stdout,
            stderr,
            status: Some(code),
            signalCode: signal,
            killed,
          })
        }
      })
    })
  }

  @module("node:child_process")
  external execFileWithCallback: (
    string,
    array<string>,
    ~options: execOptions=?,
    ~callback: execCallback,
  ) => childProcess = "execFile"

  let execFileAsync: (
    string,
    ~args: array<string>=?,
    ~options: execOptions=?,
  ) => promise<execResult> = (cmd, ~args=?, ~options=?) => {
    Promise.make((resolve, _reject) => {
      let opts = switch options {
      | Some(o) => o
      | None => {}
      }
      let argsArr = switch args {
      | Some(a) => a
      | None => []
      }
      let _ = execFileWithCallback(cmd, argsArr, ~options=opts, ~callback=(err, stdout, stderr) => {
        if Nullable.isNullable(err) {
          resolve({
            stdout,
            stderr,
            status: Some(0),
            signalCode: None,
            killed: false,
          })
        } else {
          let errObj = Nullable.toOption(err)->Option.getOrThrow
          let (signal, killed) = extractExecError(errObj)
          let code = extractExitCode(errObj)
          resolve({
            stdout,
            stderr,
            status: Some(code),
            signalCode: signal,
            killed,
          })
        }
      })
    })
  }

  let execShellCommand: (
    ~command: string,
    ~cwd: string=?,
  ) => promise<result<string, string>> = async (~command, ~cwd=?) => {
    try {
      let options: execOptions = {
        ?cwd,
        shell: true,
        encoding: "utf8",
      }
      let result = await execAsync(command, ~options)
      if result.killed {
        Error("Command timed out")
      } else {
        switch result.status {
        | Some(0) => Ok(result.stdout)
        | Some(code) => Error("Command exited with code " ++ Int.toString(code))
        | None => Error("Command exited unexpectedly")
        }
      }
    } catch {
    | JsExn(obj) =>
      let message = switch JsExn.message(obj) {
      | Some(m) => m
      | None => "Unknown error"
      }
      Error(message)
    }
  }
}

module Readline = {
  type interface = {
    question: string => promise<string>,
    close: unit => unit,
  }

  type completer = (string, int) => promise<(array<string>, int)>

  type readlineInterface = {
    question: (string, ~completer: completer=?) => promise<string>,
    close: unit => unit,
  }

  type streamReadable
  type streamWritable

  @module("node:process") external stdin: streamReadable = "stdin"
  @module("node:process") external stdout: streamWritable = "stdout"

  @module("node:readline")
  external createInterface: (
    ~input: streamReadable,
    ~output: streamWritable=?,
    unit,
  ) => readlineInterface = "createInterface"
}

module Util = {
  @unboxed
  type defaultValue =
    | String(string)
    | Bool(bool)

  type flagConfig = {
    @as("type") type_: string,
    short?: string,
    default?: defaultValue,
    multiple?: bool,
  }

  type cliOptions = {
    help?: bool,
    version?: bool,
    name?: string,
    input?: string,
    output?: string,
    format?: string,
    verbose?: bool,
  }

  type parseResults = {
    values: cliOptions,
    positionals: array<string>,
  }

  type parseConfig = {
    args: array<string>,
    options: dict<flagConfig>,
    strict?: bool,
    allowPositionals?: bool,
    tokens?: bool,
  }

  @module("node:util")
  external parseArgs: parseConfig => parseResults = "parseArgs"

  @module("node:util")
  external inspect: 'a => string = "inspect"

  let parseOptions: (~short: string=?, ~default: defaultValue=?, unit) => flagConfig = (
    ~short=?,
    ~default=?,
    (),
  ) => {
    type_: "string",
    ?short,
    ?default,
  }

  let getString: (cliOptions, string) => option<string> = (values, key) => {
    switch key {
    | "name" => values.name
    | "input" => values.input
    | "output" => values.output
    | "format" => values.format
    | _ => None
    }
  }

  let getBool: (cliOptions, string) => bool = (values, key) => {
    switch key {
    | "help" => values.help->Option.getOr(false)
    | "version" => values.version->Option.getOr(false)
    | "verbose" => values.verbose->Option.getOr(false)
    | _ => false
    }
  }
}

module NodeProcess = {
  @module("node:process") external argv: array<string> = "argv"
  @module("node:process") external env: dict<string> = "env"
  @module("node:process") external exit: int => unit = "exit"
  @module("node:process") external cwd: unit => string = "cwd"
}

module ParseArgs = Util
