/**
 * NodeJsProcess — Node.js process adapter implementing Ports.process.
 */

open NodeJs

let onSignal: (string, unit => unit) => unit = %raw(`(signal, callback) => process.on(signal, callback)`)
let removeSignalListeners: unit => unit = %raw(`() => { process.removeAllListeners("SIGINT"); process.removeAllListeners("SIGTERM"); }`)

let make: unit => Ports.process = () => {
  cwd: NodeProcess.cwd,
  env: () => NodeProcess.env,
  argv: () => NodeProcess.argv,
  exit: NodeProcess.exit,
  onSignal,
  removeSignalListeners,
}
