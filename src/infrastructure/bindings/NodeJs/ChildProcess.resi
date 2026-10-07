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

let execFileAsync: (string, ~args: array<string>=?, ~options: execOptions=?) => promise<execResult>
