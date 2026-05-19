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
  external join3: (string, string, string) => string = "join"

  @module("node:path")
  external resolve: (string, string) => string = "resolve"

  @module("node:path")
  external relative: (string, string) => string = "relative"

  @module("node:path")
  external dirname: string => string = "dirname"

  @module("node:path")
  external basename: (string, ~ext: string=?) => string = "basename"

  @module("node:path")
  external extname: string => string = "extname"

  @module("node:path")
  external isAbsolute: string => bool = "isAbsolute"

  @module("node:path")
  external normalize: string => string = "normalize"

  @module("node:path")
  external sep: string = "sep"

  @module("node:path")
  external delimiter: string = "delimiter"
}

module Os = {
  @module("node:os")
  external tmpdir: unit => string = "tmpdir"

  @module("node:os")
  external homedir: unit => string = "homedir"

  @module("node:os")
  external hostname: unit => string = "hostname"

  @module("node:os")
  external platform: unit => string = "platform"

  @module("node:os")
  external arch: unit => string = "arch"

  type cpusTimes = {user: int, nice: int, sys: int, idle: int, irq: int}
  type cpusInfo = {
    model: string,
    speed: int,
    times: cpusTimes,
  }

  @module("node:os")
  external cpus: unit => array<cpusInfo> = "cpus"

  @module("node:os")
  external totalmem: unit => int = "totalmem"

  @module("node:os")
  external freemem: unit => int = "freemem"

  @module("node:os")
  external loadavg: unit => array<float> = "loadavg"

  @module("node:os")
  external uptime: unit => int = "uptime"

  type networkInterfaceInfo = {
    address: string,
    family: string,
    netmask: string,
    mac: string,
    internal: bool,
  }

  @module("node:os")
  external networkInterfaces: unit => dict<array<networkInterfaceInfo>> = "networkInterfaces"

  type userInfoOptions = {encoding: string}
  type userInfoResult = {username: string, uid: int, gid: int, shell: string, homedir: string}

  @module("node:os")
  external userInfo: (~options: userInfoOptions=?) => userInfoResult = "userInfo"

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
  type spawnOptions = {
    cwd?: string,
    env?: dict<string>,
    shell?: bool,
    timeout?: int,
    stdio?: array<string>,
  }

  type childProcess = {
    pid: int,
    stdout: unit,
    stderr: unit,
    status?: int,
    signal?: string,
  }

  @module("node:child_process")
  external spawn: (~command: string, ~args: array<string>, ~options: spawnOptions=?) => childProcess =
    "spawn"

  type execResult = {stdout: string, stderr: string, status: option<int>, signalCode: option<string>, killed: bool}

  type execOptions = {
    cwd?: string,
    env?: dict<string>,
    shell?: bool,
    encoding?: string,
    timeout?: int,
  }

  @module("node:child_process")
  external exec: (string, ~options: execOptions=?) => promise<execResult> = "exec"

  @module("node:child_process")
  external execSync: (string, ~options: spawnOptions=?) => string = "execSync"

  type execSyncOptions = {
    cwd?: string,
    env?: dict<string>,
    shell?: bool,
    input?: string,
    encoding?: string,
    timeout?: int,
    maxBuffer?: int,
  }

  @module("node:child_process")
  external execFileSync: (string, ~args: array<string>=?, ~options: execSyncOptions=?) => string =
    "execFileSync"

  @module("node:child_process")
  external execFile: (string, ~args: array<string>=?, ~options: execOptions=?) => promise<execResult> =
    "execFile"

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
      let result = await exec(command, ~options)
      Ok(result.stdout)
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

  @module("readline")
  external createInterface: (
    ~input: streamReadable,
    ~output: streamWritable=?,
    unit,
  ) => readlineInterface = "createInterface"

  @module("readline")
  external moveCursor: (streamReadable, int, int) => unit = "moveCursor"

  @module("readline")
  external clearLine: (streamReadable, int) => unit = "clearLine"

  @module("readline")
  external cursorTo: (streamReadable, int, ~y: int=?, unit) => unit = "cursorTo"
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

module NodeTimers = {
  @module("node:timers") external setTimeout: (unit => unit, int) => int = "setTimeout"
  @module("node:timers") external clearTimeout: int => unit = "clearTimeout"
}

module ParseArgs = Util
