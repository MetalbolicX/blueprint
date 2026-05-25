/**
 * NodeJsShell — Node.js child_process adapter implementing Ports.shell.
 */

open NodeJs.ChildProcess

let make: unit => Ports.shell = () => {
  execShellCommand: execShellCommand,
  execAsync: (cmd, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.ChildProcess.execOptions))
    | None => None
    }
    (execAsync(cmd, ~options=?opts) :> promise<Ports.execResult>)
  },
  execFileAsync: (cmd, ~args=?, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.ChildProcess.execOptions))
    | None => None
    }
    (NodeJs.ChildProcess.execFileAsync(cmd, ~args?, ~options=?opts) :> promise<Ports.execResult>)
  },
}