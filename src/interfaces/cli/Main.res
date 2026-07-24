// CLI entry point — invoked by Node when dist/main.mjs runs
let _ = Cli.main()->Promise.catch(e => {
  let msg = Errors.extractErrorMessage(e)
  Console.error("Fatal: " ++ msg)
  NodeJs.Process.exit(1)
  Promise.resolve()
})
