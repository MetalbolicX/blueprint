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
type statResult = {isDirectory: unit => bool, isFile: unit => bool}

type fileSystem = {
  readFile: (string, ~options: readFileOptions=?) => promise<string>,
  writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit>,
  mkdir: (string, ~options: mkdirOptions=?) => promise<string>,
  rm: (string, ~options: rmOptions=?) => promise<unit>,
  cp: (string, string, ~options: cpOptions=?) => promise<unit>,
  readdir: (string, ~options: readdirOptions=?) => promise<array<string>>,
  fileExists: string => promise<bool>,
  stat: string => promise<statResult>,
  makeStagingDir: unit => string,
}

type process = {
  cwd: unit => string,
  env: unit => dict<string>,
  argv: unit => array<string>,
  exit: int => unit,
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
  shell?: bool,
  encoding?: string,
  timeout?: int,
}

type shell = {
  execShellCommand: (~command: string, ~cwd: string=?) => promise<result<string, string>>,
  execAsync: (string, ~options: shellOptions=?) => promise<execResult>,
}

type path = {
  join: (string, string) => string,
  resolve: (string, string) => string,
  dirname: string => string,
  isAbsolute: string => bool,
  basename: (string, ~ext: string=?) => string,
}

type deps = {
  fs: fileSystem,
  path: path,
  process: process,
  shell: shell,
}