/**
 * NodeJsShell — Node.js child_process adapter implementing Ports.shell.
 */

let make: unit => Ports.shell = () => {
  execFileAsync: (cmd, ~args=?, ~options=?) => {
    let opts = switch options {
    | Some(o) => Some((o :> NodeJs.ChildProcess.execOptions))
    | None => None
    }
    (NodeJs.ChildProcess.execFileAsync(cmd, ~args?, ~options=?opts) :> promise<Ports.execResult>)
  },
}
