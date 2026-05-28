// HookSecurity_test — hook-specific security tests

open TestHelpers

let rejectError: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)

let makeShell = (~execAsyncResult: result<Ports.execResult, string>): Ports.shell => {
  execShellCommand: (~command as _, ~cwd=?) => Promise.resolve(Ok("")),
  execAsync: (_cmd, ~options=?) =>
    switch execAsyncResult {
    | Ok(result) => Promise.resolve(result)
    | Error(message) => rejectError(message)
    },
  execFileAsync: (_cmd, ~args=?, ~options=?) =>
    Promise.resolve(({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}: Ports.execResult)),
}

let makeProcess = (): Ports.process => {
  cwd: () => "/workspace/project",
  env: () => Dict.make(),
  argv: () => ["node", "blueprint"],
  exit: _ => (),
  onSignal: (_, _) => (),
  removeSignalListeners: () => (),
}

suite("HookSecurity", () => {
  testAsync("executeHook: script outside project tree is blocked", resolve => {
    let hook: Config.hookCommand = {command: "/etc/malicious.sh"}

    Hooks.executeHook(
      ~hook,
      ~cwd="/workspace/project",
      ~timeout=1000,
      ~hookType=Hooks.PreGenerate,
      ~shellEnv=None,
      ~shell=makeShell(~execAsyncResult=Ok({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false})),
      ~process=makeProcess(),
      ~path=NodeJsPath.make(),
      ~fs=NodeJsFileSystem.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "outside project tree"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  test("executeHook: sensitive env vars are filtered", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "AWS_SECRET_KEY", "secret")
    Dict.set(inheritedEnv, "PATH", "/usr/bin")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    assert_false(Dict.has(result, "AWS_SECRET_KEY"))
  })

  testAsync("executeHook: timeout is respected", resolve => {
    let hook: Config.hookCommand = {command: "sleep 10"}

    Hooks.executeHook(
      ~hook,
      ~cwd="/workspace/project",
      ~timeout=100,
      ~hookType=Hooks.PreGenerate,
      ~shellEnv=None,
      ~shell=makeShell(~execAsyncResult=Error("hook timed out")),
      ~process=makeProcess(),
      ~path=NodeJsPath.make(),
      ~fs=NodeJsFileSystem.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "timed out"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("executeHook: relative path traversal is blocked", resolve => {
    let hook: Config.hookCommand = {command: "../../../etc/evil.sh"}

    Hooks.executeHook(
      ~hook,
      ~cwd="/workspace/project",
      ~timeout=1000,
      ~hookType=Hooks.PreGenerate,
      ~shellEnv=None,
      ~shell=makeShell(~execAsyncResult=Ok({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false})),
      ~process=makeProcess(),
      ~path=NodeJsPath.make(),
      ~fs=NodeJsFileSystem.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "outside project tree"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("phase1: missing tool fails before shell queue is created", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")
    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())
    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [Template.To("src/<%= Name %>.tsx"), Template.Tool("eslint")],
      body: "export default '<%= Name %>'",
    }

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs=NodeJsFileSystem.make(),
        ~path=NodeJsPath.make(),
        ~process=NodeJsProcess.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(err) => {
          assert_true(String.includes(err.message, "Tool not found"))
          NodeJs.Fs.fileExists(err.stagingDir)
        }
      | Ok(_) => {
          assert_false(true)
          Promise.resolve(false)
        }
      }
    })
    ->Promise.then(stagingStillExists => {
      assert_false(stagingStillExists)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("phase1: missing script fails before shell queue is created", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")
    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())
    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [Template.To("src/<%= Name %>.tsx"), Template.Script("setup")],
      body: "export default '<%= Name %>'",
    }

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=Some({enabled: true}),
        ~fs=NodeJsFileSystem.make(),
        ~path=NodeJsPath.make(),
        ~process=NodeJsProcess.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(err) => {
          assert_true(String.includes(err.message, "Script not found"))
          NodeJs.Fs.fileExists(err.stagingDir)
        }
      | Ok(_) => {
          assert_false(true)
          Promise.resolve(false)
        }
      }
    })
    ->Promise.then(stagingStillExists => {
      assert_false(stagingStillExists)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
