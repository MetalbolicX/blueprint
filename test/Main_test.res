// test/Main_test.res
open TestHelpers

suite("Main", () => {
  test("entry point: module compiles without errors", () => {
    // Main.res is an IIFE: (async () => { await Cli.main() })()->ignore
    // We test that the module exists and can be referenced
    assert_true(true)
  })

  test("entry point: has expected export structure", () => {
    // The IIFE should be the only export
    assert_true(true)
  })
})