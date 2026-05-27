open TestHelpers

suite("NodeJsProcess adapter", () => {
  test("cwd returns current working directory", () => {
    let p = NodeJsProcess.make()
    let cwd = p.cwd()
    assert_true(String.length(cwd) > 0)
  })

  test("env returns process environment variables", () => {
    let p = NodeJsProcess.make()
    assert_true(Dict.size(p.env()) >= 0)
  })

  test("argv returns command line arguments", () => {
    let p = NodeJsProcess.make()
    let argv = p.argv()
    assert_true(Array.length(argv) >= 1)
    switch Array.get(argv, 0) {
    | Some(first) => assert_true(String.endsWith(first, "node"))
    | None => assert_true(false)
    }
  })
})
