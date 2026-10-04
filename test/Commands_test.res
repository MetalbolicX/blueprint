open TestHelpers

let makeTrackingFs = (~readdirCalls: ref<int>, ~writeCalls: ref<int>): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()
  {
    readFile: (file, ~options=?) => base.readFile(file, ~options?),
    writeFile: (file, content, ~options=?) => {
      writeCalls.contents = writeCalls.contents + 1
      base.writeFile(file, content, ~options?)
    },
    mkdir: (dir, ~options=?) => base.mkdir(dir, ~options?),
    rm: (dir, ~options=?) => base.rm(dir, ~options?),
    cp: (fromPath, toPath, ~options=?) => base.cp(fromPath, toPath, ~options?),
    readdir: (dir, ~options=?) => {
      readdirCalls.contents = readdirCalls.contents + 1
      base.readdir(dir, ~options?)
    },
    fileExists: file => base.fileExists(file),
    stat: file => base.stat(file),
    lstat: file => base.lstat(file),
    realpath: file => base.realpath(file),
    makeStagingDir: prefix => base.makeStagingDir(prefix),
  }
}

let makeDeps = (
  ~cwd: string,
  ~exitCodes: ref<array<int>>,
  ~_loggedMessages: ref<array<string>>,
  ~shellCalls: ref<int>,
): Ports.deps => {
  let fs = NodeJsFileSystem.make()
  let path = NodeJsPath.make()
  // Patch globalThis.console.error to capture messages for assertions
  let _ = %raw("console.error = function(msg) { globalThis.__testMessages.push(msg); }")
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
      homedir: () => "/tmp/test-home",
    },
    shell: {
      execAsync: (command, ~options=?) => {
        shellCalls.contents = shellCalls.contents + 1
        NodeJsShell.make().execAsync(command, ~options?)
      },
      execFileAsync: (file, ~args=?, ~options=?) => {
        shellCalls.contents = shellCalls.contents + 1
        NodeJsShell.make().execFileAsync(file, ~args?, ~options?)
      },
    },
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

suite("Commands", () => {
  testAsync("runGenerate: invalid timeout exits before discovery runs", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let readdirCalls = ref(0)
    let writeCalls = ref(0)
    let shellCalls = ref(0)
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
  // Store reference so the raw JS can push to it
  let _ = %raw("globalThis.__testMessages = []")
  let fs = makeTrackingFs(~readdirCalls, ~writeCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~_loggedMessages=loggedMessages, ~shellCalls)
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
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_true(Array.length(msgs) >= 1)
      // plan 052: the invalid timeout is rejected during config parsing, before CLI validation.
      assert_true(
        switch Array.get(msgs, 0) {
        | Some(msg) =>
          msg->String.includes(
            "Error: Invalid project config " ++ NodeJs.Path.join(tmpDir, ".blueprint.yaml") ++ ": timeout must be >= 1",
          )
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
    let writeCalls = ref(0)
    let shellCalls = ref(0)
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
  // Store reference so the raw JS can push to it
  let _ = %raw("globalThis.__testMessages = []")
  let fs = makeTrackingFs(~readdirCalls, ~writeCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~_loggedMessages=loggedMessages, ~shellCalls)
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
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))
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

  testAsync("runGenerate: malformed project config fails closed before discovery or writes", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let readdirCalls = ref(0)
    let writeCalls = ref(0)
    let shellCalls = ref(0)
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
    let _ = %raw("globalThis.__testMessages = []")
    let fs = makeTrackingFs(~readdirCalls, ~writeCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~_loggedMessages=loggedMessages, ~shellCalls)
    let path = NodeJsPath.make()
    let configPath = NodeJs.Path.join(tmpDir, ".blueprint.yaml")

    NodeJs.Fs.writeFile(configPath, "dry_run: [unclosed")
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
      assert_eq(Array.length(exitCodes.contents), 1)
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))
      assert_eq(readdirCalls.contents, 0)
      assert_eq(writeCalls.contents, 0)
      assert_eq(shellCalls.contents, 0)
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_true(
        switch Array.get(msgs, 0) {
        | Some(msg) => msg->String.includes("Invalid project config " ++ configPath)
        | None => false
        }
      )
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("loadConfigContext: valid dry_run project config is preserved", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let path = NodeJsPath.make()
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
    let shellCalls = ref(0)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~_loggedMessages=loggedMessages, ~shellCalls)

    NodeJs.Fs.writeFile(NodeJs.Path.join(tmpDir, ".blueprint.yaml"), "dry_run: true\n")
    ->Promise.then(_ => ConfigContext.loadConfigContext(~deps, ~fs, ~path))
    ->Promise.then(result => {
      assert_true(
        switch result {
        | Ok(ctx) => ctx.merged.dryRun
        | Error(_) => false
        }
      )
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("loadConfigContext: absent project config uses defaults", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let path = NodeJsPath.make()
    let exitCodes = ref([])
    let loggedMessages: ref<array<string>> = ref([])
    let shellCalls = ref(0)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~_loggedMessages=loggedMessages, ~shellCalls)

    ConfigContext.loadConfigContext(~deps, ~fs, ~path)
    ->Promise.then(result => {
      assert_true(
        switch result {
        | Ok(ctx) => !ctx.merged.dryRun && ctx.projectConfig == None
        | Error(_) => false
        }
      )
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
