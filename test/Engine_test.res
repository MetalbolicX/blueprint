// Engine_test — full pipeline e2e tests

open TestHelpers
open EngineResult
open EngineLifecycle

let deps: Ports.deps = {
  fs: NodeJsFileSystem.make(),
  path: NodeJsPath.make(),
  process: NodeJsProcess.make(),
  shell: NodeJsShell.make(),
  interactiveIO: NodeJsInteractiveIO.make(()),
  argParser: NodeJsArgParser.make(),
  yamlParser: NodeJsYamlParser.make(),
  ejs: NodeJsEjs.make(),
}

let staleThresholdMs = 5 * 60 * 1000

let makeCleanupFs = (
  ~tmpRoot: string,
  ~tmpEntries: array<string>,
  ~existingPaths: array<string>=[],
  ~directoryPaths: array<string>=[],
  ~removed: ref<array<string>>,
): Ports.fileSystem => {
  readFile: (_, ~options as _=?) => Promise.resolve(""),
  writeFile: (_, _, ~options as _=?) => Promise.resolve(),
  mkdir: (_, ~options as _=?) => Promise.resolve(""),
  rm: (target, ~options as _=?) => {
    removed.contents->Array.push(target)->ignore
    Promise.resolve()
  },
  cp: (_, _, ~options as _=?) => Promise.resolve(),
  readdir: (target, ~options as _=?) => Promise.resolve(target == tmpRoot ? tmpEntries : []),
  fileExists: target => Promise.resolve(existingPaths->Array.some(path => path == target)),
  stat: target =>
    Promise.resolve({
      isDirectory: () => directoryPaths->Array.some(path => path == target),
      isFile: () => !(directoryPaths->Array.some(path => path == target)),
      isSymbolicLink: () => false,
    }: Ports.statResult),
  lstat: _target =>
    Promise.resolve({
      isDirectory: () => false,
      isFile: () => false,
      isSymbolicLink: () => false,
    }: Ports.statResult),
  realpath: target => Promise.resolve(target),
  makeStagingDir: prefix => Promise.resolve(tmpRoot ++ "/" ++ prefix ++ "-test"),
}

let makeSignalProcess = (
  ~registeredSignals: ref<array<string>>,
  ~exitCodes: ref<array<int>>,
  ~removedListeners: ref<int>,
  ~sigintHandler: ref<option<unit => unit>>,
  ~sigtermHandler: ref<option<unit => unit>>,
): Ports.process => {
  cwd: () => "/workspace/project",
  env: () => Dict.make(),
  argv: () => ["node", "blueprint"],
  exit: code => exitCodes.contents->Array.push(code)->ignore,
  onSignal: (signal, callback) => {
    registeredSignals.contents->Array.push(signal)->ignore
    switch signal {
    | "SIGINT" => sigintHandler.contents = Some(callback)
    | "SIGTERM" => sigtermHandler.contents = Some(callback)
    | _ => ()
    }
  },
  removeSignalListeners: () => removedListeners.contents = removedListeners.contents + 1,
  homedir: () => "/home/test",
}

let invokeHandler = (handlerRef: ref<option<unit => unit>>) => {
  switch handlerRef.contents {
  | Some(callback) => callback()
  | None => assert_false(true)
  }
}

suite("Engine", () => {
  test("generateResult: structure", () => {
    let result: generateResult = {
      filesCreated: 3,
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
    let result: generateResult = {
      filesCreated: 0,
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
      | Error(e) => assert_true(String.includes(e.message, "pre_generate hook failed"))
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
      | Error(e) => assert_true(String.includes(e.message, "post_generate hook failed"))
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
      | Error(e) => assert_true(String.includes(e.message, "pre_generate hook failed"))
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
      | Error(_) => {
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      }
    })
    ->Promise.catch(_ => {
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("registerSignalHandlers: cleans active staging dir for SIGINT and SIGTERM before exit", resolve => {
    let removed = ref([])
    let registeredSignals = ref([])
    let exitCodes = ref([])
    let removedListeners = ref(0)
    let sigintHandler = ref(None)
    let sigtermHandler = ref(None)
    let proc = makeSignalProcess(~registeredSignals, ~exitCodes, ~removedListeners, ~sigintHandler, ~sigtermHandler)
    let fs = makeCleanupFs(~tmpRoot="/tmp/engine-signal-cleanup", ~tmpEntries=[], ~removed)
    let stagingDirRef = ref(Some("/tmp/blueprint-signal-int"))

    registerSignalHandlers(~process=proc, ~stagingDirRef, ~fs)
    invokeHandler(sigintHandler)

    Promise.resolve()
    ->Promise.then(_ => {
      Promise.resolve()
    })
    ->Promise.then(_ => {
      assert_eq(Array.get(registeredSignals.contents, 0), Some("SIGINT"))
      assert_eq(Array.get(registeredSignals.contents, 1), Some("SIGTERM"))
      assert_eq(Array.get(removed.contents, 0), Some("/tmp/blueprint-signal-int"))
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))

      stagingDirRef.contents = Some("/tmp/blueprint-signal-term")
      invokeHandler(sigtermHandler)
      Promise.resolve()
    })
    ->Promise.then(_ => {
      assert_eq(Array.get(removed.contents, 1), Some("/tmp/blueprint-signal-term"))
      assert_eq(Array.get(exitCodes.contents, 1), Some(1))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("registerSignalHandlers: signal before staging dir exists exits without cleanup", resolve => {
    let removed = ref([])
    let registeredSignals = ref([])
    let exitCodes = ref([])
    let removedListeners = ref(0)
    let sigintHandler = ref(None)
    let sigtermHandler = ref(None)
    let proc = makeSignalProcess(~registeredSignals, ~exitCodes, ~removedListeners, ~sigintHandler, ~sigtermHandler)
    let fs = makeCleanupFs(~tmpRoot="/tmp/engine-signal-no-staging", ~tmpEntries=[], ~removed)
    let stagingDirRef = ref(None)

    registerSignalHandlers(~process=proc, ~stagingDirRef, ~fs)
    invokeHandler(sigintHandler)

    Promise.resolve()
    ->Promise.then(_ => {
      assert_eq(Array.get(registeredSignals.contents, 0), Some("SIGINT"))
      assert_eq(Array.get(registeredSignals.contents, 1), Some("SIGTERM"))
      assert_eq(Array.length(removed.contents), 0)
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("cleanupOrphans: removes stale blueprint staging dirs", resolve => {
    let nowMs = Date.now()->Float.toInt
    let tmpRoot = "/tmp/engine-cleanup-stale"
    let staleDirName = "blueprint-" ++ Int.toString(nowMs - staleThresholdMs - 1000) ++ "-stale"
    let staleDirPath = deps.path.join(tmpRoot, staleDirName)
    let removed = ref([])
    let fs = makeCleanupFs(~tmpRoot, ~tmpEntries=[staleDirName], ~directoryPaths=[staleDirPath], ~removed)

    cleanupOrphans(~outputDir="/tmp/output", ~fs, ~path=deps.path, ~tmpRoot)
    ->Promise.then(_ => {
      assert_eq(Array.get(removed.contents, 0), Some(staleDirPath))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("cleanupOrphans: preserves fresh blueprint staging dirs", resolve => {
    let nowMs = Date.now()->Float.toInt
    let tmpRoot = "/tmp/engine-cleanup-fresh"
    let freshDirName = "blueprint-" ++ Int.toString(nowMs - 1000) ++ "-fresh"
    let freshDirPath = deps.path.join(tmpRoot, freshDirName)
    let removed = ref([])
    let fs = makeCleanupFs(~tmpRoot, ~tmpEntries=[freshDirName], ~directoryPaths=[freshDirPath], ~removed)

    cleanupOrphans(~outputDir="/tmp/output", ~fs, ~path=deps.path, ~tmpRoot)
    ->Promise.then(_ => {
      assert_eq(Array.length(removed.contents), 0)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("cleanupOrphans: removes blueprint backup leak dirs", resolve => {
    let tmpRoot = "/tmp/engine-cleanup-backup"
    let outputDir = "/tmp/output-with-backup"
    let backupDir = deps.path.join(outputDir, ".blueprint-backup")
    let removed = ref([])
    let fs = makeCleanupFs(~tmpRoot, ~tmpEntries=[], ~existingPaths=[backupDir], ~removed)

    cleanupOrphans(~outputDir, ~fs, ~path=deps.path, ~tmpRoot)
    ->Promise.then(_ => {
      assert_eq(Array.get(removed.contents, 0), Some(backupDir))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("cleanupOrphans: no stale dirs does not remove tmp paths", resolve => {
    let nowMs = Date.now()->Float.toInt
    let tmpRoot = "/tmp/engine-cleanup-none-stale"
    let freshDirName = "blueprint-" ++ Int.toString(nowMs - 1000) ++ "-fresh-only"
    let freshDirPath = deps.path.join(tmpRoot, freshDirName)
    let removed = ref([])
    let fs = makeCleanupFs(~tmpRoot, ~tmpEntries=[freshDirName], ~directoryPaths=[freshDirPath], ~removed)

    cleanupOrphans(~outputDir="/tmp/output", ~fs, ~path=deps.path, ~tmpRoot)
    ->Promise.then(_ => {
      assert_eq(Array.length(removed.contents), 0)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("cleanupOrphans: no backup leak does not remove backup path", resolve => {
    let tmpRoot = "/tmp/engine-cleanup-no-backup"
    let outputDir = "/tmp/output-without-backup"
    let removed = ref([])
    let fs = makeCleanupFs(~tmpRoot, ~tmpEntries=[], ~removed)

    cleanupOrphans(~outputDir, ~fs, ~path=deps.path, ~tmpRoot)
    ->Promise.then(_ => {
      assert_eq(Array.length(removed.contents), 0)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: cleans orphaned staging dirs and backup leaks before execution", resolve => {
    let nowMs = Date.now()->Float.toInt
    let staleDirName = "blueprint-" ++ Int.toString(nowMs - staleThresholdMs - 1000) ++ "-run"
    let staleDirPath = deps.path.join(NodeJs.Os.tmpdir(), staleDirName)
    let outputDir = deps.path.join(NodeJs.Os.tmpdir(), "engine-output-run-" ++ Int.toString(nowMs))
    let backupDir = deps.path.join(outputDir, ".blueprint-backup")
    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    Promise.all([
      NodeJs.Fs.mkdir(staleDirPath, ~options={recursive: true}),
      NodeJs.Fs.mkdir(backupDir, ~options={recursive: true}),
    ])
    ->Promise.then(_ => Engine.run(~generator=gen, ~name="CleanupRun", ~cliAttributes=Dict.make(), ~outputDir, ~force=true, ~deps))
    ->Promise.then(_ => Promise.all([deps.fs.fileExists(staleDirPath), deps.fs.fileExists(backupDir)]))
    ->Promise.then(results => {
      assert_eq(Array.get(results, 0), Some(false))
      assert_eq(Array.get(results, 1), Some(false))
      Promise.resolve()
    })
    ->Promise.then(_ => {
      NodeJs.Fs.rm(outputDir, ~options={recursive: true})
      ->Promise.catch(_ => Promise.resolve())
    })
    ->Promise.then(_ => {
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: registers signal handlers around phase2 and removes them after completion", resolve => {
    let registeredSignals = ref([])
    let exitCodes = ref([])
    let removedListeners = ref(0)
    let sigintHandler = ref(None)
    let sigtermHandler = ref(None)
    let proc = makeSignalProcess(~registeredSignals, ~exitCodes, ~removedListeners, ~sigintHandler, ~sigtermHandler)
    let outputDir = deps.path.join(NodeJs.Os.tmpdir(), "engine-output-signals-" ++ Int.toString(Date.now()->Float.toInt))
    let testDeps: Ports.deps = {
      fs: deps.fs,
      path: deps.path,
      process: proc,
      shell: deps.shell,
      interactiveIO: NodeJsInteractiveIO.make(()),
      argParser: deps.argParser,
      yamlParser: deps.yamlParser,
      ejs: deps.ejs,
    }
    let gen: Discovery.generator = {
      name: "component",
      path: "/tmp/blueprint-test-nonexistent",
      templates: [],
    }

    Engine.run(
      ~generator=gen,
      ~name="SignalsRun",
      ~cliAttributes=Dict.make(),
      ~outputDir,
      ~force=true,
      ~deps=testDeps,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => {
          assert_eq(Array.get(registeredSignals.contents, 0), Some("SIGINT"))
          assert_eq(Array.get(registeredSignals.contents, 1), Some("SIGTERM"))
          assert_eq(removedListeners.contents, 1)
          assert_eq(Array.length(exitCodes.contents), 0)
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(outputDir, ~options={recursive: true})
      ->Promise.catch(_ => Promise.resolve())
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->ignore
  })
})
