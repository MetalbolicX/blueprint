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
      path: "/tmp/blueprint-test-nonexistent",
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

  testAsync("run: skips pre-hook when no config provided", resolve => {
    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
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
      | Ok(_) => assert_true(true)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: aborts pipeline when preGenerate hook fails", resolve => {
    let cfg: Config.config = {
      hooks: {
        preGenerate: "exit 1",
        timeout: 1,
      },
    }

    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/blueprint-test-output",
      ~force=true,
      ~config=cfg,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "pre_generate"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns error when postGenerate hook fails", resolve => {
    let cfg: Config.config = {
      hooks: {
        postGenerate: "exit 1",
        timeout: 1,
      },
    }

    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/blueprint-test-output",
      ~force=true,
      ~config=cfg,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "post_generate"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns Ok when preGenerate hook succeeds", resolve => {
    let cfg: Config.config = {
      hooks: {
        preGenerate: "echo ok",
        timeout: 1,
      },
    }

    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/blueprint-test-output",
      ~force=true,
      ~config=cfg,
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

  testAsync("run: returns Ok when both hooks succeed", resolve => {
    let cfg: Config.config = {
      hooks: {
        preGenerate: "echo pre-ok",
        postGenerate: "echo post-ok",
        timeout: 1,
      },
    }

    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/blueprint-test-output",
      ~force=true,
      ~config=cfg,
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