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
    hooks: NodeJsHooks.make(),
  }
}

suite("InitGlobal", () => {
  testAsync("runInitGlobal: fresh run creates global config and hello-world example", resolve => {
    let tempHome = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tempHome, ~exitCodes, ~homedir=tempHome)
    let path = NodeJsPath.make()
    let globalRoot = Utils.globalTemplateRegistryRoot(~deps)
    let globalConfigPath = path.join(path.join(tempHome, ".config"), "blueprint/config.yaml")
    let globalExamplePath = path.join(path.join(path.join(globalRoot, "hello-world"), "new"), "hello.ejs.t")
    let globalManifestPath = path.join(path.join(globalRoot, "hello-world"), "manifest.yaml")

    Commands.runInitGlobal(~deps)
    ->Promise.then(_ => {
      let configExists = deps.fs.fileExists(globalConfigPath)
      let exampleExists = deps.fs.fileExists(globalExamplePath)
      let manifestExists = deps.fs.fileExists(globalManifestPath)
      Promise.all([configExists, exampleExists, manifestExists])
    })
    ->Promise.then(results => {
      let configExists = switch Array.get(results, 0) { | Some(v) => v | None => false }
      let exampleExists = switch Array.get(results, 1) { | Some(v) => v | None => false }
      let manifestExists = switch Array.get(results, 2) { | Some(v) => v | None => false }
      assert_true(configExists)
      assert_true(exampleExists)
      assert_true(manifestExists)
      deps.fs.readFile(globalConfigPath, ~options={encoding: "utf8"})
    })
    ->Promise.then(configContent => {
      assert_true(String.includes(configContent, "templates:"))
      assert_true(String.includes(configContent, "force_overwrite:"))
      deps.fs.readFile(globalExamplePath, ~options={encoding: "utf8"})
    })
    ->Promise.then(exampleContent => {
      assert_true(String.startsWith(exampleContent, "---"))
      assert_true(String.includes(exampleContent, "to: hello-<"))
      assert_true(String.includes(exampleContent, "Hello,"))
      deps.fs.readFile(globalManifestPath, ~options={encoding: "utf8"})
    })
    ->Promise.then(manifestContent => {
      assert_true(String.includes(manifestContent, "classification: hello-world"))
      assert_true(String.includes(manifestContent, "name: hello-world"))
      assert_eq(exitCodes.contents->Array.length, 0)
      NodeJs.Fs.rm(tempHome, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runInitGlobal: second run is idempotent no-op", resolve => {
    let tempHome = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tempHome, ~exitCodes, ~homedir=tempHome)
    let path = NodeJsPath.make()
    let globalRoot = Utils.globalTemplateRegistryRoot(~deps)
    let globalConfigPath = path.join(path.join(tempHome, ".config"), "blueprint/config.yaml")
    let globalExamplePath = path.join(path.join(path.join(globalRoot, "hello-world"), "new"), "hello.ejs.t")

    Commands.runInitGlobal(~deps)
    ->Promise.then(_ => {
      deps.fs.readFile(globalConfigPath, ~options={encoding: "utf8"})
    })
    ->Promise.then(configContent1 => {
      deps.fs.readFile(globalExamplePath, ~options={encoding: "utf8"})
      ->Promise.then(exampleContent1 => {
        Commands.runInitGlobal(~deps)
        ->Promise.then(_ => {
          deps.fs.readFile(globalConfigPath, ~options={encoding: "utf8"})
        })
        ->Promise.then(configContent2 => {
          deps.fs.readFile(globalExamplePath, ~options={encoding: "utf8"})
          ->Promise.then(exampleContent2 => {
            assert_eq(configContent1, configContent2)
            assert_eq(exampleContent1, exampleContent2)
            assert_eq(exitCodes.contents->Array.length, 0)
            NodeJs.Fs.rm(tempHome, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        })
      })
    })
    ->ignore
  })

  testAsync("runInitGlobal: does NOT touch pre-existing global user generators", resolve => {
    let tempHome = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tempHome, ~exitCodes, ~homedir=tempHome)
    let path = NodeJsPath.make()
    let globalRoot = Utils.globalTemplateRegistryRoot(~deps)
    let userGenPath = path.join(path.join(path.join(globalRoot, "usergen"), "new"), "x.txt")
    deps.fs.mkdir(path.join(path.join(globalRoot, "usergen"), "new"), ~options={recursive: true})
      ->Promise.then(_ => deps.fs.writeFile(userGenPath, "GLOBAL_USER_CONTENT"))
      ->Promise.then(_ => Commands.runInitGlobal(~deps))
      ->Promise.then(_ => deps.fs.readFile(userGenPath, ~options={encoding: "utf8"}))
      ->Promise.then(userContent => {
        assert_eq(userContent, "GLOBAL_USER_CONTENT")
        let globalExamplePath = path.join(path.join(path.join(globalRoot, "hello-world"), "new"), "hello.ejs.t")
        deps.fs.fileExists(globalExamplePath)
        ->Promise.then(exampleExists => {
          assert_true(exampleExists)
          assert_eq(exitCodes.contents->Array.length, 0)
          NodeJs.Fs.rm(tempHome, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
      })
      ->ignore
  })
})
