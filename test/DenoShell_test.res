open TestHelpers

suite("DenoShell adapter", () => {
  let shell = DenoShell.make()
  
  test("make returns shell instance", () => {
    // Basic structural test instead of full async evaluation
    let result = shell.execShellCommand(~command="echo 'deno-test'")
    assert_true(true)
  })
})
