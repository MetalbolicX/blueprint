/**
 * Node.js child_process bindings — subprocess execution
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

// Callback-based exec for proper async handling
// The callback receives (error, stdout, stderr)
type execCallback = (Nullable.t<JsExn.t>, string, string) => unit

@module("node:child_process")
external execWithCallback: (
  string,
  ~options: execOptions=?,
  ~callback: execCallback,
) => childProcess = "exec"

// Typed view of Node.js child_process error fields.
// Node.js errors carry fields ReScript's JsExn.t doesn't expose:
//   - signal: string | null (SIGTERM, SIGKILL, etc.)
//   - killed: boolean (process was killed by timeout)
//   - code: number (exit code, defaults to 1)
// We type the view via a record with `Nullable.t` fields so reading the
// optional JS properties is explicit. The single cast from JsExn.t lives
// at the helper boundary below.
type execError = {
  signal: Nullable.t<string>,
  killed: Nullable.t<bool>,
  code: Nullable.t<int>,
}

// Extract Node.js error properties (signal, killed) from Js.Exn.t.
// Returns tuple: (signalCode, killed)
let extractExecError: JsExn.t => (option<string>, bool) = e => {
  let err: execError = Obj.magic(e)
  (Nullable.toOption(err.signal), Nullable.toOption(err.killed)->Option.getOr(false))
}

// Extract exit code from Node.js error, defaulting to 1.
// Node.js error.code is the exit code; if missing/undefined, assume 1.
let extractExitCode: JsExn.t => int = e => {
  let err: execError = Obj.magic(e)
  Nullable.toOption(err.code)->Option.getOr(1)
}

// Shared callback wrapper — extracts error, builds execResult
let wrapExecResult = (invoke: (~callback: execCallback) => childProcess): promise<execResult> => {
  Promise.make((resolve, _reject) => {
    let _ = invoke(~callback=(err, stdout, stderr) => {
      if Nullable.isNullable(err) {
        resolve({stdout, stderr, status: Some(0), signalCode: None, killed: false})
      } else {
        let errObj = Nullable.toOption(err)->Option.getOrThrow
        let (signal, killed) = extractExecError(errObj)
        let code = extractExitCode(errObj)
        resolve({stdout, stderr, status: Some(code), signalCode: signal, killed})
      }
    })
  })
}

// Properly typed async exec using callback API internally
let execAsync: (
  string,
  ~options: execOptions=?,
) => promise<execResult> = (cmd, ~options=?) => {
  let opts = switch options {
  | Some(o) => o
  | None => {}
  }
  wrapExecResult((~callback) => execWithCallback(cmd, ~options=opts, ~callback))
}

@module("node:child_process")
external execFileWithCallback: (
  string,
  array<string>,
  ~options: execOptions=?,
  ~callback: execCallback,
) => childProcess = "execFile"

let execFileAsync: (
  string,
  ~args: array<string>=?,
  ~options: execOptions=?,
) => promise<execResult> = (cmd, ~args=?, ~options=?) => {
  let opts = switch options {
  | Some(o) => o
  | None => {}
  }
  let argsArr = switch args {
  | Some(a) => a
  | None => []
  }
  wrapExecResult((~callback) => execFileWithCallback(cmd, argsArr, ~options=opts, ~callback))
}
