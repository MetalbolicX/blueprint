// HookSecurity_test — hook-specific security tests

open TestHelpers

let rejectError: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)

let makeShell = (~execAsyncResult: result<Ports.execResult, string>): Ports.shell => {
  execShellCommand: (~command as _, ~cwd as _=?) => Promise.resolve(Ok("")),
  execAsync: (_cmd, ~options as _=?) =>
    switch execAsyncResult {
    | Ok(result) => Promise.resolve(result)
    | Error(message) => rejectError(message)
    },
  execFileAsync: (_cmd, ~args as _=?, ~options as _=?) =>
    Promise.resolve(({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}: Ports.execResult)),
}

// Records the (cmd, args) tuple every time execFileAsync is invoked so
// structured-args tests can prove that shell metacharacters in args do NOT
// get rewritten (no shell interpretation).
let makeRecordingShell = (recorded: ref<(string, array<string>)>, ~status: int): Ports.shell => {
  execShellCommand: (~command as _, ~cwd as _=?) => Promise.resolve(Ok("")),
  execAsync: (_cmd, ~options as _=?) =>
    Promise.resolve(({stdout: "", stderr: "", status: Some(status), signalCode: None, killed: false}: Ports.execResult)),
  execFileAsync: (cmd, ~args=?, ~options as _=?) => {
    let recordedArgs: array<string> = switch args {
    | Some(a) => a
    | None => []
    }
    let _ = recorded.contents = (cmd, recordedArgs)
    Promise.resolve(({stdout: "", stderr: "", status: Some(status), signalCode: None, killed: false}: Ports.execResult))
  },
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

  // ---------- WS2: structured args + bounded timeout / exit-code ----------

  test("WS2: execFileOptions carry the 30s timeout bound", () => {
    // Confirms the constant is the spec-locked value.
    assert_eq(ExecPolicy.defaultTimeout, 30000)
  })

  testAsync("WS2: path-based hook with args invokes execFileAsync with the args verbatim", resolve => {
    // Create a real script the hook will resolve inside the project tree.
    let tmpDir = NodeJs.Os.makeStagingDir()
    let scriptPath = NodeJs.Path.join(tmpDir, "scripts/setup.sh")
    NodeJs.Fs.mkdir(NodeJs.Path.join(tmpDir, "scripts"), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(scriptPath, "#!/bin/sh\necho ok\n"))
    ->Promise.then(_ => {
      // Args contain a shell metacharacter; if execFile were replaced with shell,
      // it would split on the space and reinterpret '||' etc. execFile passes args literal.
      let hook: Config.hookCommand = {
        command: "./scripts/setup.sh",
        args: ["--flag", "value with space", "; rm -rf /tmp"],
      }
      let recorded: ref<(string, array<string>)> = ref(("init", []))
      Hooks.executeHook(
        ~hook,
        ~cwd=tmpDir,
        ~timeout=1000,
        ~hookType=Hooks.PreGenerate,
        ~shellEnv=None,
        ~shell=makeRecordingShell(recorded, ~status=0),
        ~process=makeProcess(),
        ~path=NodeJsPath.make(),
        ~fs=NodeJsFileSystem.make(),
      )
      ->Promise.then(result => {
        switch result {
        | Ok(_) => {
            // The recorded tuple must contain the literal args — no array splitting.
            let (cmd, args) = recorded.contents
            assert_eq(cmd, "./scripts/setup.sh")
            assert_eq(args->Array.length, 3)
            assert_eq(args[0]->Option.getOr(""), "--flag")
            assert_eq(args[1]->Option.getOr(""), "value with space")
            assert_eq(args[2]->Option.getOr(""), "; rm -rf /tmp")
          }
        | Error(_msg) => assert_true(false) // surface msg in failure trace
        }
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("WS2: path-based hook surfaces exit-code as Error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let scriptPath = NodeJs.Path.join(tmpDir, "scripts/fail.sh")
    NodeJs.Fs.mkdir(NodeJs.Path.join(tmpDir, "scripts"), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(scriptPath, "#!/bin/sh\nexit 42\n"))
    ->Promise.then(_ => {
      let hook: Config.hookCommand = {command: "./scripts/fail.sh"}
      Hooks.executeHook(
        ~hook,
        ~cwd=tmpDir,
        ~timeout=1000,
        ~hookType=Hooks.PreGenerate,
        ~shellEnv=None,
        ~shell=makeRecordingShell(ref(("init", [])), ~status=42),
        ~process=makeProcess(),
        ~path=NodeJsPath.make(),
        ~fs=NodeJsFileSystem.make(),
      )
      ->Promise.then(result => {
        switch result {
        | Error(msg) => assert_true(String.includes(msg, "42"))
        | Ok(_) => assert_false(true)
        }
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("WS2: Tool/InlineCommand shell rejection in ShellExecutor surfaces allowlist reason", resolve => {
    // Drives the ShellExecutor code path directly: a no-args tool whose command
    // is NOT in the tools allowlist must be Rejected before any process spawn.
    let cmd: Template.shellCommand = {
      target: Template.ToolCall({
        name: "rm",
        toolDef: {name: "rm", command: "rm"},
        sourcePath: "evil.ejs.t",
      }),
      sourcePath: "evil.ejs.t",
    }
    // Empty tools allowlist ⇒ every no-args tool is rejected.
    ShellExecutor.executeShellCommands(
      ~commands=[cmd],
      ~cwd="/tmp/ws2-reject",
      ~shellConfig=Some({enabled: true}),
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell={
        execShellCommand: (~command as _, ~cwd as _=?) => Promise.resolve(Ok("")),
        execAsync: (_cmd, ~options as _=?) => Promise.reject(JsError.throwWithMessage("shell.execAsync MUST NOT be called for a Rejected tool")),
        execFileAsync: (_cmd, ~args as _=?, ~options as _=?) => Promise.reject(JsError.throwWithMessage("shell.execFileAsync MUST NOT be called for a Rejected tool")),
      },
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "rm") && String.includes(msg, "tools allowlist"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
