/**
 * NodeJsHooks — adapter for the lifecycle hooks port.
 */

let make: unit => Ports.hooks = () => {
  run: Hooks.run,
}
