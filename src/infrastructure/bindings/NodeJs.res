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

  @module("node:fs/promises")
  external readFile: (string, ~options: readFileOptions=?) => promise<string> = "readFile"

  @module("node:fs/promises")
  external writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit> = "writeFile"

  @module("node:fs/promises")
  external mkdir: (string, ~options: mkdirOptions=?) => promise<string> = "mkdir"

  @module("node:fs/promises")
  external rm: (string, ~options: rmOptions=?) => promise<unit> = "rm"

  @module("node:fs/promises")
  external cp: (string, string, ~options: cpOptions=?) => promise<unit> = "cp"

  @module("node:fs/promises")
  external readdir: (string, ~options: readdirOptions=?) => promise<array<string>> = "readdir"

  @module("node:fs/promises")
  external stat: string => promise<statResult> = "stat"

  @module("node:fs/promises")
  external access: (string, ~mode: int=?) => promise<unit> = "access"

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
    let randomPart = Math.random()->Float.toString->String.slice(~start=2)
    Path.join(tmpdir(), "fluxo-" ++ randomPart)
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

  type execResult = {stdout: string, stderr: string, status: option<int>}

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
      switch result.status {
      | Some(0) => Ok(result.stdout)
      | _ => Error(result.stderr)
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
  type optionConfig = {"type": string, "short": option<string>, "default": option<string>}

  type parseArgsConfig = {
    args: option<array<string>>,
    options: option<dict<optionConfig>>,
    strict: option<bool>,
    allowPositionals: option<bool>,
    tokens: option<bool>,
    stopEarly: option<bool>,
    ignoreCrashes: option<bool>,
  }

  type parsedValues = dict<string>

  type parsedArgs = {
    values: parsedValues,
    positionals: array<string>,
    tokens: option<array<string>>,
  }

  @module("node:util")
  external parseArgs: parseArgsConfig => parsedArgs = "parseArgs"

  @module("node:util")
  external inspect: 'a => string = "inspect"

  let parseOptions: (~short: string=?, ~default: string=?, unit) => optionConfig = (
    ~short=?,
    ~default=?,
    (),
  ) =>
    {
      "type": "string",
      "short": short,
      "default": default,
    }

  let getString: (parsedValues, string) => option<string> = (values, key) => {
    Dict.get(values, key)
  }

  let getBool: (parsedValues, string) => bool = (values, key) => {
    switch Dict.get(values, key) {
    | Some(v) => v == "true"
    | None => false
    }
  }
}

module ParseArgs = Util
