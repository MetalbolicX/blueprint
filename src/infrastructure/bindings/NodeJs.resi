module Fs: {
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

  let readFile: (string, ~options: readFileOptions=?) => promise<string>
  let writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit>
  let mkdir: (string, ~options: mkdirOptions=?) => promise<string>
  let rm: (string, ~options: rmOptions=?) => promise<unit>
  let cp: (string, string, ~options: cpOptions=?) => promise<unit>
  let readdir: (string, ~options: readdirOptions=?) => promise<array<string>>
  let stat: string => promise<statResult>
  let access: (string, ~mode: int=?) => promise<unit>

  let fOk: int
  let fileExists: string => promise<bool>
}

module Path: {
  let join: (string, string) => string
  let join3: (string, string, string) => string
  let resolve: (string, string) => string
  let relative: (string, string) => string
  let dirname: string => string
  let basename: (string, ~ext: string=?) => string
  let extname: string => string
  let isAbsolute: string => bool
  let normalize: string => string
  let sep: string
  let delimiter: string
}

module Os: {
  type cpusTimes = {user: int, nice: int, sys: int, idle: int, irq: int}

  type cpusInfo = {
    model: string,
    speed: int,
    times: cpusTimes,
  }

  type networkInterfaceInfo = {
    address: string,
    family: string,
    netmask: string,
    mac: string,
    internal: bool,
  }

  type userInfoOptions = {encoding: string}

  type userInfoResult = {
    username: string,
    uid: int,
    gid: int,
    shell: string,
    homedir: string,
  }

  let tmpdir: unit => string
  let homedir: unit => string
  let hostname: unit => string
  let platform: unit => string
  let arch: unit => string
  let cpus: unit => array<cpusInfo>
  let totalmem: unit => int
  let freemem: unit => int
  let loadavg: unit => array<float>
  let uptime: unit => int
  let networkInterfaces: unit => dict<array<networkInterfaceInfo>>
  let userInfo: (~options: userInfoOptions=?) => userInfoResult

  let makeStagingDir: unit => string
}

module ChildProcess: {
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

  type execResult = {stdout: string, stderr: string, status: option<int>, signalCode: option<string>, killed: bool}

  type execOptions = {
    cwd?: string,
    env?: dict<string>,
    shell?: bool,
    encoding?: string,
    timeout?: int,
  }

  type execSyncOptions = {
    cwd?: string,
    env?: dict<string>,
    shell?: bool,
    input?: string,
    encoding?: string,
    timeout?: int,
    maxBuffer?: int,
  }

  let spawn: (~command: string, ~args: array<string>, ~options: spawnOptions=?) => childProcess
  let exec: (string, ~options: execOptions=?) => childProcess
  let execWithCallback: (string, ~options: execOptions=?, ~callback: (Nullable.t<JsExn.t>, string, string) => unit) => childProcess
  let execAsync: (string, ~options: execOptions=?) => promise<execResult>
  let execSync: (string, ~options: spawnOptions=?) => string
  let execFileSync: (string, ~args: array<string>=?, ~options: execSyncOptions=?) => string
  let execFileAsync: (string, ~args: array<string>=?, ~options: execOptions=?) => promise<execResult>
  let execShellCommand: (~command: string, ~cwd: string=?) => promise<result<string, string>>
}

module Readline: {
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

  let stdin: streamReadable
  let stdout: streamWritable

  let createInterface: (~input: streamReadable, ~output: streamWritable=?, unit) => readlineInterface
  let moveCursor: (streamReadable, int, int) => unit
  let clearLine: (streamReadable, int) => unit
  let cursorTo: (streamReadable, int, ~y: int=?, unit) => unit
}

module Util: {
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

  let parseArgs: parseConfig => parseResults
  let inspect: 'a => string
  let parseOptions: (~short: string=?, ~default: defaultValue=?, unit) => flagConfig
  let getString: (cliOptions, string) => option<string>
  let getBool: (cliOptions, string) => bool
}

module ParseArgs = Util

module NodeProcess: {
  let argv: array<string>
  let env: dict<string>
  let exit: int => unit
  let cwd: unit => string
}
