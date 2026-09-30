// ChildProcess_test — child_process execFile binding tests.

open TestHelpers

suite("NodeJs.ChildProcess", () => {
  testAsync("execFileAsync runs a structured command", resolve => {
    NodeJs.ChildProcess.execFileAsync("node", ~args=["-e", "process.stdout.write('child-ok')"])
    ->Promise.then(result => {
      assert_eq(result.status, Some(0))
      assert_eq(result.stdout, "child-ok")
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
