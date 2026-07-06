/**
 * NodeJsProcess — Node.js process adapter implementing Ports.process.
 */

open NodeJs

@val @scope("process") external processOn: (string, unit => unit) => unit = "on"
@val @scope("process") external processRemoveAllListeners: string => unit = "removeAllListeners"

let onSignal: (string, unit => unit) => unit = processOn
let removeSignalListeners: unit => unit = () => {
  processRemoveAllListeners("SIGINT")
  processRemoveAllListeners("SIGTERM")
}

let make: unit => Ports.process = () => {
  cwd: NodeProcess.cwd,
  env: () => NodeProcess.env,
  argv: () => NodeProcess.argv,
  exit: NodeProcess.exit,
  onSignal,
  removeSignalListeners,
  homedir: NodeJs.Os.homedir,
}
