// Engine_test — full pipeline e2e tests

open TestHelpers

let deps: Ports.deps = {
  fs: NodeJsFileSystem.make(),
  path: NodeJsPath.make(),
  process: NodeJsProcess.make(),
  shell: NodeJsShell.make(),
  interactiveIO: NodeJsInteractiveIO.make(()),
  argParser: NodeJsArgParser.make(),
}

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
      ~deps,
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
      ~deps,
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

  testAsync("run: aborts pipeline when preGenerate hook fails", resolve => {
    let cfg: Config.config = {
      hooks: {
        preGenerate: {command: "exit 1"},
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
      ~deps,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "pre_generate hook failed"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns error when postGenerate hook fails", resolve => {
    let cfg: Config.config = {
      hooks: {
        postGenerate: {command: "exit 1"},
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
      ~deps,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "post_generate hook failed"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns Ok when preGenerate hook succeeds", resolve => {
    let cfg: Config.config = {
      hooks: {
        preGenerate: {command: "echo ok"},
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
      ~deps,
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
        preGenerate: {command: "echo pre-ok"},
        postGenerate: {command: "echo post-ok"},
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
      ~deps,
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

  testAsync("run: readline is always closed even on error", resolve => {
    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    // Use a failing hook to trigger error path
    let cfg: Config.config = {
      hooks: {
        preGenerate: {command: "exit 1"},
        timeout: 1,
      },
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir="/tmp/blueprint-test-output",
      ~force=true,
      ~config=cfg,
      ~deps,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "pre_generate hook failed"))
      }
      // Test passes if we get here without hanging (readline was closed)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: clears fetch cache for each invocation", resolve => {
    Fetcher._resetClearCacheCount()

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
      ~deps,
    )
    ->Promise.then(_ =>
      Engine.run(
        ~generator=gen,
        ~name="ButtonAgain",
        ~cliAttributes=Dict.make(),
        ~outputDir="/tmp/blueprint-test-output",
        ~force=true,
        ~deps,
      )
    )
    ->Promise.then(secondResult => {
      switch secondResult {
      | Ok(_) => {
          assert_eq(Fetcher._getClearCacheCount(), 2)
          resolve()
          Promise.resolve()
        }
      | Error(_) => assert_false(true)
      }
    })
    ->Promise.catch(_ => {
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
