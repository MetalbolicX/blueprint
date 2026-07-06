/**
 * Deno process adapter implementing Ports.process.
 */

open Deno

// Bindings for Deno global properties related to process
@val @scope("Deno") external cwd: unit => string = "cwd"
@val @scope("Deno") external args: array<string> = "args"
@val @scope("Deno") external exit: int => unit = "exit"

let env: unit => dict<string> = () => Fs.envToObject()

// Deno doesn't expose os.homedir() directly; resolve from the HOME env var.
// Falls back to USERPROFILE for Windows hosts and the placeholder /tmp for
// environments where neither is set (e.g. minimal sandboxes).
let homedir: unit => string = () => {
  let envObj = Fs.envToObject()
  switch Dict.get(envObj, "HOME") {
  | Some(h) if String.length(h) > 0 => h
  | _ =>
    switch Dict.get(envObj, "USERPROFILE") {
    | Some(h) if String.length(h) > 0 => h
    | _ => "/tmp"
    }
  }
}

let make: unit => Ports.process = () => {
  let listeners: ref<array<(string, unit => unit)>> = ref([])
  let onSignal = (signal, callback) => {
    Signal.addSignalListener(signal, callback)
    listeners := Array.concat(listeners.contents, [(signal, callback)])
  }
  let removeSignalListeners = () => {
    listeners.contents->Array.forEach(((signal, callback)) => Signal.removeSignalListener(signal, callback))
    listeners := []
  }

  {
    cwd: cwd,
    env: env,
    // We prepend dummy node/script args so that cli parsing works the same
    // as it does for Node where args are Array.slice(~start=2)
    argv: () => Array.concat(["deno", "blueprint"], args),
    exit: exit,
    onSignal: onSignal,
    removeSignalListeners: removeSignalListeners,
    homedir: homedir,
  }
}
