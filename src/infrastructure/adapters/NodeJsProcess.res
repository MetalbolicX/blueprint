/**
 * NodeJsProcess — Node.js process adapter implementing Ports.process.
 */

open NodeJs

let make: unit => Ports.process = () => {
  cwd: NodeProcess.cwd,
  env: () => NodeProcess.env,
  argv: () => NodeProcess.argv,
  exit: NodeProcess.exit,
}