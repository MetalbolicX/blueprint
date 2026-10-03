open TestHelpers

let makeDeps = (
  ~cwd: string,
  ~exitCodes: ref<array<int>>,
  ~homedir: string,
): Ports.deps => {
  let fs = NodeJsFileSystem.make()
  let path = NodeJsPath.make()
  {
    fs,
    path,
    process: {
      cwd: () => cwd,
      env: () => Dict.make(),
      argv: () => ["node", "blueprint"],
      exit: code => {
        let _ = exitCodes.contents->Array.push(code)
        ()
      },
      onSignal: (_, _) => (),
      removeSignalListeners: () => (),
      homedir: () => homedir,
    },
    shell: NodeJsShell.make(),
    interactiveIO: {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(false),
      close: () => (),
    },
    argParser: {
      parse: (~args as _, ~strict as _, ~allowPositionals as _) => Ok({values: Dict.make(), positionals: []}),
    },
    yamlParser: NodeJsYamlParser.make(),
    ejs: NodeJsEjs.make(),
    fetcher: NodeJsFetcher.make(),
    pathSecurity: NodeJsPathSecurity.make(),
    shellBuilder: NodeJsShellBuilder.make(),
    envFilter: NodeJsEnvFilter.make(),
  }
}

suite("Init", () => {
  testAsync("runInit: fresh run creates config and hello-world example", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~homedir="/tmp/test-home")
    let path = NodeJsPath.make()
    let configPath = path.join(tmpDir, ".blueprint.yaml")
    let examplePath = path.join(path.join(path.join(tmpDir, "_templates"), "hello-world/new"), "hello.ejs.t")
    let manifestPath = path.join(path.join(tmpDir, "_templates"), "hello-world/manifest.yaml")

    Commands.runInit(~deps)
    ->Promise.then(_ => {
      let configExists = deps.fs.fileExists(configPath)
      let exampleExists = deps.fs.fileExists(examplePath)
      let manifestExists = deps.fs.fileExists(manifestPath)
      Promise.all([configExists, exampleExists, manifestExists])
    })
    ->Promise.then(results => {
      let configExists = switch Array.get(results, 0) { | Some(v) => v | None => false }
      let exampleExists = switch Array.get(results, 1) { | Some(v) => v | None => false }
      let manifestExists = switch Array.get(results, 2) { | Some(v) => v | None => false }
      assert_true(configExists)
      assert_true(exampleExists)
      assert_true(manifestExists)
      deps.fs.readFile(configPath, ~options={encoding: "utf8"})
    })
    ->Promise.then(configContent => {
      assert_true(String.includes(configContent, "generators:"))
      deps.fs.readFile(examplePath, ~options={encoding: "utf8"})
    })
    ->Promise.then(exampleContent => {
      assert_true(String.startsWith(exampleContent, "---"))
      assert_true(String.includes(exampleContent, "to: hello-<"))
      assert_true(String.includes(exampleContent, "Hello,"))
      deps.fs.readFile(manifestPath, ~options={encoding: "utf8"})
    })
    ->Promise.then(manifestContent => {
      assert_true(String.includes(manifestContent, "classification: hello-world"))
      assert_true(String.includes(manifestContent, "name: hello-world"))
      assert_eq(exitCodes.contents->Array.length, 0)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runInit: second run is idempotent no-op (files unchanged, no exit)", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~homedir="/tmp/test-home")
    let path = NodeJsPath.make()
    let configPath = path.join(tmpDir, ".blueprint.yaml")
    let examplePath = path.join(path.join(path.join(tmpDir, "_templates"), "hello-world/new"), "hello.ejs.t")

    Commands.runInit(~deps)
    ->Promise.then(_ => {
      deps.fs.readFile(configPath, ~options={encoding: "utf8"})
    })
    ->Promise.then(configContent1 => {
      deps.fs.readFile(examplePath, ~options={encoding: "utf8"})
      ->Promise.then(exampleContent1 => {
        Commands.runInit(~deps)
        ->Promise.then(_ => {
          deps.fs.readFile(configPath, ~options={encoding: "utf8"})
        })
        ->Promise.then(configContent2 => {
          deps.fs.readFile(examplePath, ~options={encoding: "utf8"})
          ->Promise.then(exampleContent2 => {
            assert_eq(configContent1, configContent2)
            assert_eq(exampleContent1, exampleContent2)
            assert_eq(exitCodes.contents->Array.length, 0)
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        })
      })
    })
    ->ignore
  })

  testAsync("runInit: does NOT touch pre-existing user generators", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~homedir="/tmp/test-home")
    let path = NodeJsPath.make()
    let userGenPath = path.join(path.join(path.join(tmpDir, "_templates"), "usergen/new"), "x.txt")
    let _ = deps.fs.mkdir(path.join(path.join(tmpDir, "_templates"), "usergen/new"), ~options={recursive: true})
      ->Promise.then(_ => deps.fs.writeFile(userGenPath, "USER_CONTENT"))
      ->Promise.then(_ => Commands.runInit(~deps))
      ->Promise.then(_ => deps.fs.readFile(userGenPath, ~options={encoding: "utf8"}))
      ->Promise.then(userContent => {
        assert_eq(userContent, "USER_CONTENT")
        let examplePath = path.join(path.join(path.join(tmpDir, "_templates"), "hello-world/new"), "hello.ejs.t")
        deps.fs.fileExists(examplePath)
        ->Promise.then(exampleExists => {
          assert_true(exampleExists)
          assert_eq(exitCodes.contents->Array.length, 0)
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
      })
      ->ignore
  })
})
