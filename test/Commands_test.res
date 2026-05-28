open TestHelpers

let makeTrackingFs = (~readdirCalls: ref<int>): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()
  {
    readFile: (file, ~options=?) => base.readFile(file, ~options?),
    writeFile: (file, content, ~options=?) => base.writeFile(file, content, ~options?),
    mkdir: (dir, ~options=?) => base.mkdir(dir, ~options?),
    rm: (dir, ~options=?) => base.rm(dir, ~options?),
    cp: (fromPath, toPath, ~options=?) => base.cp(fromPath, toPath, ~options?),
    readdir: (dir, ~options=?) => {
      readdirCalls.contents = readdirCalls.contents + 1
      base.readdir(dir, ~options?)
    },
    fileExists: file => base.fileExists(file),
    stat: file => base.stat(file),
    makeStagingDir: () => base.makeStagingDir(),
    realpath: file => base.realpath(file),
  }
}

let makeDeps = (
  ~cwd: string,
  ~exitCodes: ref<array<int>>,
  ~loggedMessages: ref<array<string>>,
): Ports.deps => {
  let fs = NodeJsFileSystem.make()
  let path = NodeJsPath.make()
  // Patch globalThis.console.error to capture messages for assertions
  %raw("console.error = function(msg) { globalThis.__testMessages.push(msg); }")
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

suite("Commands", () => {
  testAsync("runGenerate: invalid timeout exits before discovery runs", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let readdirCalls = ref(0)
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
    // Store reference so the raw JS can push to it
    %raw("globalThis.__testMessages = []")
    let fs = makeTrackingFs(~readdirCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~loggedMessages)
    let path = NodeJsPath.make()

    NodeJs.Fs.writeFile(
      NodeJs.Path.join(tmpDir, ".blueprint.yaml"),
      "hooks:\n  timeout: 0\n",
    )
    ->Promise.then(_ =>
      Commands.runGenerate(
        ~fs,
        ~path,
        ~deps,
        ~classification="component",
        ~name="Button",
        ~force=false,
        ~outputDir=NodeJs.Path.join(tmpDir, "out"),
        ~cliAttributes=Dict.make(),
      )
    )
    ->Promise.then(_ => {
      assert_eq(readdirCalls.contents, 0)
      assert_eq(Array.length(exitCodes.contents), 1)
      assert_eq(exitCodes.contents[0], Some(1))
      // Verify validation error message is emitted (Commands.res wraps with "Error: " prefix)
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_true(Array.length(msgs) >= 1)
      assert_true(
        switch Array.get(msgs, 0) {
        | Some(msg) => msg->String.includes("Error: timeout must be >= 1")
        | None => false
        }
      )
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runGenerate: shell enabled without tools exits before discovery runs", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let readdirCalls = ref(0)
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
    // Store reference so the raw JS can push to it
    %raw("globalThis.__testMessages = []")
    let fs = makeTrackingFs(~readdirCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~loggedMessages)
    let path = NodeJsPath.make()

    NodeJs.Fs.writeFile(
      NodeJs.Path.join(tmpDir, ".blueprint.yaml"),
      "shell:\n  enabled: true\n",
    )
    ->Promise.then(_ =>
      Commands.runGenerate(
        ~fs,
        ~path,
        ~deps,
        ~classification="component",
        ~name="Button",
        ~force=false,
        ~outputDir=NodeJs.Path.join(tmpDir, "out"),
        ~cliAttributes=Dict.make(),
      )
    )
    ->Promise.then(_ => {
      assert_eq(readdirCalls.contents, 0)
      assert_eq(Array.length(exitCodes.contents), 1)
      assert_eq(exitCodes.contents[0], Some(1))
      // Verify validation error message is emitted (Commands.res wraps with "Error: " prefix)
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_true(Array.length(msgs) >= 1)
      assert_true(
        switch Array.get(msgs, 0) {
        | Some(msg) => msg->String.includes("Error: shell.enabled=true requires tools to be defined")
        | None => false
        }
      )
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
