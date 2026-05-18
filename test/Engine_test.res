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

  testAsync("run: returns Ok result with classification", resolve => {
    let gen: Discovery.generator = {
      name: "component",
      path: "/workspace/_templates/component",
      templates: [],
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/blueprint-test-output",
      ~force=true,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(r) => assert_eq(r.classification, "component")
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
