open TestHelpers

suite("NodeJsShell adapter", () => {
  let shell = NodeJsShell.make()

  testAsync("execFileAsync returns explicit metadata on non-zero exit (failure)", resolve => {
    shell.execFileAsync("node", ~args=["-e", "process.exit(3)"])
    ->Promise.then(r => {
      assert_true(r.status == Some(3))
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(e => {
      Console.log2("Test caught rejection:", e)
      // Should not reject!
      assert_true(false)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
