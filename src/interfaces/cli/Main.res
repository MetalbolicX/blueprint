// CLI entry point — invoked by Node when dist/main.mjs runs
let _ = Cli.main()->Promise.catch(e => {
  let msg = switch JsExn.message(e->Obj.magic) {
  | Some(m) => m
  | None => "unknown error"
  }
  Console.error("Fatal: " ++ msg)
  NodeJs.NodeProcess.exit(1)
  Promise.resolve()
})
