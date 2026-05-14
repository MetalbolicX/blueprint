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
  cwd: option<string>,
  env: option<dict<string>>,
  shell: option<bool>,
  input: option<string>,
  encoding: option<string>,
  timeout: option<int>,
  maxBuffer: option<int>,
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
