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
  let resolve: (string, string) => string
  let dirname: string => string
  let basename: (string, ~ext: string=?) => string
  let isAbsolute: string => bool
}

module Os: {
  let tmpdir: unit => string
  let homedir: unit => string

  let makeStagingDir: unit => string
}

module ChildProcess: {
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

  let execWithCallback: (string, ~options: execOptions=?, ~callback: (Nullable.t<JsExn.t>, string, string) => unit) => childProcess
  let execAsync: (string, ~options: execOptions=?) => promise<execResult>
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
