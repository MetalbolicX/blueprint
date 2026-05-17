type spawnOptions = {
  cwd: option<string>,
  env: option<dict<string>>,
  shell: option<bool>,
  timeout: option<int>,
  stdio: option<array<string>>,
}

type childProcess = {
  pid: int,
  stdout: unit,
  stderr: unit,
  status: option<int>,
  signal: option<string>,
}

type execResult = {stdout: string, stderr: string, status: option<int>}

type execOptions = {
  cwd?: string,
  env?: dict<string>,
  shell?: bool,
  encoding?: string,
  timeout?: int,
}

type execSyncOptions = {
  cwd: option<string>,
  env: option<dict<string>>,
  shell: option<bool>,
  input: option<string>,
  encoding: option<string>,
  timeout: option<int>,
  maxBuffer: option<int>,
}

let spawn: (~command: string, ~args: array<string>, ~options: spawnOptions=?) => childProcess
let exec: (string, ~options: execOptions=?) => promise<execResult>
let execSync: (string, ~options: spawnOptions=?) => string
let execFileSync: (string, ~args: array<string>=?, ~options: execSyncOptions=?) => string

let execShellCommand: (~command: string, ~cwd: string=?) => promise<result<string, string>>
