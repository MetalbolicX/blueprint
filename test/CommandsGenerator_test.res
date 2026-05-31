// CommandsGenerator_test — testing pure and async logic

open TestHelpers

let makeDeps = (~cwd: string, ~exitCodes: ref<array<int>>): Ports.deps => {
  let path = NodeJsPath.make()
  let fs = NodeJsFileSystem.make()
  
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
    },
    shell: NodeJsShell.make(),
    interactiveIO: {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes=?) => Promise.resolve(false),
      close: () => (),
    },
    argParser: {
      parse: (~args as _, ~strict as _, ~allowPositionals as _) => Ok({values: Dict.make(), positionals: []}),
    },
  }
}

suite("CommandsGenerator", () => {
  test("normalizeTemplateFilename: appends .ejs.t if missing", () => {
    assert_eq(CommandsGenerator.normalizeTemplateFilename("test"), "test.ejs.t")
    assert_eq(CommandsGenerator.normalizeTemplateFilename("test.ejs.t"), "test.ejs.t")
    assert_eq(CommandsGenerator.normalizeTemplateFilename("test.tmpl"), "test.tmpl")
  })

  test("isTemplateFile: returns true for valid templates", () => {
    assert_true(CommandsGenerator.isTemplateFile("test.ejs.t"))
    assert_true(CommandsGenerator.isTemplateFile("test.tmpl"))
    assert_false(CommandsGenerator.isTemplateFile("test.js"))
    assert_false(CommandsGenerator.isTemplateFile("test"))
  })

  testAsync("resolveGeneratorDir: finds generator in correct path", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
    let generatorPath = NodeJs.Path.join(NodeJs.Path.join(tmpDir, "_templates"), "my-gen")
    
    NodeJs.Fs.mkdir(generatorPath, ~options={recursive: true})
    ->Promise.then(_ => CommandsGenerator.resolveGeneratorDir(~deps, ~name="my-gen"))
    ->Promise.then(result => {
      switch result {
      | Some(path) => assert_eq(path, generatorPath)
      | None => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolveGeneratorDir: returns None if not found", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
    
    NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ => CommandsGenerator.resolveGeneratorDir(~deps, ~name="nonexistent"))
    ->Promise.then(result => {
      switch result {
      | Some(_) => assert_false(true)
      | None => assert_true(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runList: exits 1 when name is None", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
    
    CommandsGenerator.runList(~deps, ~name=None)
    ->Promise.then(_ => {
      assert_eq(exitCodes.contents[0], Some(1))
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runList: exits 1 when generator not found", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
    
  let _ = %raw("globalThis.__testMessages = []")
  let _ = %raw("console.error = function(msg) { globalThis.__testMessages.push(msg); }")

    CommandsGenerator.runList(~deps, ~name=Some("not-found"))
    ->Promise.then(_ => {
      assert_eq(exitCodes.contents[0], Some(1))
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_true(Array.length(msgs) >= 1)
      assert_true(
        switch Array.get(msgs, 0) {
        | Some(msg) => msg->String.includes("generator not found")
        | None => false
        }
      )
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runList: prints generator details", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
    let generatorPath = NodeJs.Path.join(NodeJs.Path.join(tmpDir, "_templates"), "my-gen")
    
  let _ = %raw("globalThis.__originalConsoleLog = console.log")
  let _ = %raw("globalThis.__testMessages = []")
  let _ = %raw("console.log = function(msg) { globalThis.__testMessages.push(msg); }")

    NodeJs.Fs.mkdir(NodeJs.Path.join(generatorPath, "new"), ~options={recursive: true})
    ->Promise.then(_ => {
      let manifestPath = NodeJs.Path.join(generatorPath, "manifest.yaml")
      NodeJs.Fs.writeFile(manifestPath, "prompts:\n  - name: feature\n    type: input\n    description: name\n")
    })
    ->Promise.then(_ => {
      let templatePath = NodeJs.Path.join(NodeJs.Path.join(generatorPath, "new"), "index.ejs.t")
      NodeJs.Fs.writeFile(templatePath, "---")
    })
    ->Promise.then(_ => CommandsGenerator.runList(~deps, ~name=Some("my-gen")))
    ->Promise.then(_ => {
      let msgs: array<string> = %raw("globalThis.__testMessages")
      // Should print Generator, Path, Prompts, Templates, etc.
      let joinedMsgs = Array.join(msgs, "\n")
      assert_true(String.includes(joinedMsgs, "Generator: my-gen"))
      assert_true(String.includes(joinedMsgs, "feature (input)"))
      assert_true(String.includes(joinedMsgs, "index.ejs.t"))
      
      let _ = %raw("console.log = globalThis.__originalConsoleLog")
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
