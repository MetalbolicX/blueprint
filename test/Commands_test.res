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

let makeDeps = (~cwd: string, ~exitCodes: ref<array<int>>): Ports.deps => {
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
    let fs = makeTrackingFs(~readdirCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
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
    let fs = makeTrackingFs(~readdirCalls)
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes)
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
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
