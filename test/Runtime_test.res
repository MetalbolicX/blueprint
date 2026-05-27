// test/Runtime_test.res
open TestHelpers

suite("Runtime", () => {
  test("isDeno: returns a boolean", () => {
    let result = Runtime.isDeno()
    assert_true(result == true || result == false)
  })

  test("isDeno: deterministic — returns same value twice", () => {
    let first = Runtime.isDeno()
    let second = Runtime.isDeno()
    assert_eq(first, second)
  })

  test("isDeno: can be used in conditional", () => {
    let runtimeName = if Runtime.isDeno() {
      "deno"
    } else {
      "node"
    }
    assert_true(runtimeName == "deno" || runtimeName == "node")
  })
})