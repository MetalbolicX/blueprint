/**
 * Ports — dependency inversion interfaces for runtime I/O operations.
 *
 * These record types define the contracts that runtime adapters must satisfy.
 * Application and infrastructure layers depend on these abstractions,
 * not on concrete Node.js bindings.
 *
 * Usage: pass port instances as labeled arguments or bundle into a deps record:
 *   type deps = { fs: fileSystem, path: path, process: process, shell: shell }
 */

type readFileOptions = {encoding: string}
type writeFileOptions = {encoding: string}
type mkdirOptions = {recursive: bool}
type rmOptions = {recursive: bool}
type cpOptions = {recursive: bool}
type readdirOptions = {withFileTypes: bool}
type statResult = {
  isDirectory: unit => bool,
  isFile: unit => bool,
  mtimeMs?: float,
}
type lstatResult = {
  isDirectory: unit => bool,
  isFile: unit => bool,
  isSymbolicLink: unit => bool,
}

type yamlParser = {
  parse: string => result<JSON.t, string>,
}

type ejs = {
  renderString: (~template: string, ~context: dict<string>) => result<string, string>,
  renderFile: (~path: string, ~context: dict<string>) => promise<result<string, string>>,
}

type fileSystem = {
  readFile: (string, ~options: readFileOptions=?) => promise<string>,
  writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit>,
  mkdir: (string, ~options: mkdirOptions=?) => promise<string>,
  rm: (string, ~options: rmOptions=?) => promise<unit>,
  cp: (string, string, ~options: cpOptions=?) => promise<unit>,
  readdir: (string, ~options: readdirOptions=?) => promise<array<string>>,
  fileExists: string => promise<bool>,
  stat: string => promise<statResult>,
  lstat: string => promise<lstatResult>,
  realpath: string => promise<string>,
  makeStagingDir: string => promise<string>,
}

type process = {
  cwd: unit => string,
  env: unit => dict<string>,
  argv: unit => array<string>,
  exit: int => unit,
  onSignal: (string, unit => unit) => unit,
  removeSignalListeners: unit => unit,
  homedir: unit => string,
}

type execResult = {
  stdout: string,
  stderr: string,
  status: option<int>,
  signalCode: option<string>,
  killed: bool,
}

type shellOptions = {
  cwd?: string,
  env?: dict<string>,
  encoding?: string,
  timeout?: int,
}

type shell = {
  execShellCommand: (~command: string, ~cwd: string=?, ~timeout: option<int>=?) => promise<result<string, string>>,
  execAsync: (string, ~options: shellOptions=?) => promise<execResult>,
  execFileAsync: (string, ~args: array<string>=?, ~options: shellOptions=?) => promise<execResult>,
}

type path = {
  join: (string, string) => string,
  resolve: (string, string) => string,
  dirname: string => string,
  isAbsolute: string => bool,
  basename: (string, ~ext: string=?) => string,
}

type interactiveIO = {
  ask: string => promise<string>,
  askConfirm: (~question: string, ~defaultYes: bool=?) => promise<bool>,
  close: unit => unit,
}

type parsedArgs = {
  values: dict<string>,
  positionals: array<string>,
}

type argParser = {
  parse: (~args: array<string>, ~strict: bool, ~allowPositionals: bool) => result<parsedArgs, string>,
}

type deps = {
  fs: fileSystem,
  path: path,
  process: process,
  shell: shell,
  interactiveIO: interactiveIO,
  argParser: argParser,
  yamlParser: yamlParser,
  ejs: ejs,
}
