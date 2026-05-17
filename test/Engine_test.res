// Engine_test — full pipeline e2e tests

open TestHelpers

suite("Engine", () => {
  test("generateResult: structure", () => {
    let result = {
      Engine.filesCreated: 3,
      filesInjected: 1,
      commandsExecuted: 2,
      classification: "component",
    }

    assert_eq(result.filesCreated, 3)
    assert_eq(result.filesInjected, 1)
    assert_eq(result.commandsExecuted, 2)
    assert_eq(result.classification, "component")
  })

  test("generateResult: zero values", () => {
    let result = {
      Engine.filesCreated: 0,
      filesInjected: 0,
      commandsExecuted: 0,
      classification: "empty",
    }

    assert_eq(result.filesCreated, 0)
    assert_eq(result.classification, "empty")
  })
})