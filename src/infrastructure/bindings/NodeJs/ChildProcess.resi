/**
 * Node.js child_process bindings interface
 */

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
  encoding?: string,
  timeout?: int,
}

let execWithCallback: (string, ~options: execOptions=?, ~callback: (Nullable.t<JsExn.t>, string, string) => unit) => childProcess
let execAsync: (string, ~options: execOptions=?) => promise<execResult>
let execFileAsync: (string, ~args: array<string>=?, ~options: execOptions=?) => promise<execResult>
let execShellCommand: (~command: string, ~cwd: string=?) => promise<result<string, string>>
