/**
 * Deno process adapter implementing Ports.process.
 */

// Bindings for Deno global properties related to process
@val @scope("Deno") external cwd: unit => string = "cwd"
@val @scope("Deno") external args: array<string> = "args"
@val @scope("Deno") external exit: int => unit = "exit"

let env: unit => dict<string> = () => Deno.Fs.envToObject()

let make: unit => Ports.process = () => {
  cwd: cwd,
  env: env,
  // We prepend dummy node/script args so that cli parsing works the same
  // as it does for Node where args are Array.slice(~start=2)
  argv: () => Array.concat(["deno", "blueprint"], args),
  exit: exit,
}
