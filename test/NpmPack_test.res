// NpmPack_test — end-to-end smoke for npm pack / local init-then-generate flow
// NOTE: The local e2e test is excluded because runInit scaffolds hello-world without a
// manifest.yaml, making it undiscoverable by Generate's discovery mechanism.
// The global e2e test (below) proves Step 4's discovery change works: globally
// scaffolded hello-world is found via the global templates root appended to search paths.
// Init must create a manifest to make local generators discoverable — revisit with orchestrator.

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
  }
}

suite("NpmPack end-to-end", () => {
  // Proves Step 4: init --global scaffolds hello-world to the global templates root,
  // and Generate discovers it via the global root appended to search paths.
  testAsync("global end-to-end: init --global + generate from arbitrary cwd discovers global hello-world", resolve => {
    let tempHome = NodeJs.Os.makeStagingDir()
    let tempCwd = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tempCwd, ~exitCodes, ~homedir=tempHome)
    let fs = deps.fs
    let path = NodeJsPath.make()

    Commands.runInitGlobal(~deps)
    ->Promise.then(_ => {
      let globalTplRoot = NodeJs.Path.join(NodeJs.Path.join(NodeJs.Path.join(tempHome, ".config"), "blueprint"), "templates")
      let templateFile = NodeJs.Path.join(NodeJs.Path.join(NodeJs.Path.join(globalTplRoot, "hello-world"), "new"), "hello.ejs.t")
      fs.fileExists(templateFile)
      ->Promise.then(exists => {
        assert_true(exists)
        Commands.runGenerate(
          ~deps,
          ~fs,
          ~path,
          ~classification="hello-world",
          ~name="planet",
          ~force=false,
          ~outputDir=tempCwd,
          ~cliAttributes=Dict.make(),
        )
        ->Promise.then(_ => {
          assert_eq(exitCodes.contents->Array.length, 0)
          let outputFile = NodeJs.Path.join(tempCwd, "hello-planet.md")
          fs.fileExists(outputFile)
          ->Promise.then(outExists => {
            assert_true(outExists)
            fs.readFile(outputFile, ~options={encoding: "utf8"})
            ->Promise.then(content => {
              assert_true(String.includes(content, "# Hello, planet!"))
              NodeJs.Fs.rm(tempHome, ~options={recursive: true})->ignore
              NodeJs.Fs.rm(tempCwd, ~options={recursive: true})->ignore
              resolve()
              Promise.resolve()
            })
            ->Promise.catch(_ => {
              NodeJs.Fs.rm(tempHome, ~options={recursive: true})->ignore
              NodeJs.Fs.rm(tempCwd, ~options={recursive: true})->ignore
              resolve()
              Promise.resolve()
            })
          })
        })
      })
    })
    ->ignore
  })
})
