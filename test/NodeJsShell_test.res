open TestHelpers

suite("NodeJsShell adapter", () => {
  let shell = NodeJsShell.make()

  testAsync("execAsync returns explicit metadata on non-zero exit (failure)", resolve => {
    // node -e "process.exit(2)"
    shell.execAsync("node -e \"process.exit(2)\"")
    ->Promise.then(r => {
      assert_true(r.status == Some(2))
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_e => {
      // Should not reject! Should return explicit result.
      assert_true(false)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

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
