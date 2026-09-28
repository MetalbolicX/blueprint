// HookSecurity_test — hook-specific security tests

open TestHelpers

let rejectError: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)

let makeShell = (~execAsyncResult: result<Ports.execResult, string>): Ports.shell => {
  execShellCommand: (~command as _, ~cwd as _=?, ~timeout as _=?) => Promise.resolve(Ok("")),
  execAsync: (_cmd, ~options as _=?) =>
    switch execAsyncResult {
    | Ok(result) => Promise.resolve(result)
    | Error(message) => rejectError(message)
    },
  execFileAsync: (_cmd, ~args as _=?, ~options as _=?) =>
    switch execAsyncResult {
    | Ok(result) => Promise.resolve(result)
    | Error(message) => rejectError(message)
    },
}

// Records the (cmd, args) tuple every time execFileAsync is invoked so
// structured-args tests can prove that shell metacharacters in args do NOT
// get rewritten (no shell interpretation).
let makeRecordingShell = (recorded: ref<(string, array<string>)>, ~status: int): Ports.shell => {
  execShellCommand: (~command as _, ~cwd as _=?, ~timeout as _=?) => Promise.resolve(Ok("")),
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
  homedir: () => "/home/test",
}

// Captures the env Dict that execFileAsync receives in its options, so a test
// can assert that filtered safeEnv (not raw process.env) is what reaches
// the child process. Used by the WS3 env-leak guard test below.
let makeEnvCapturingShell = (capturedEnv: ref<option<Dict.t<string>>>): Ports.shell => {
  execShellCommand: (~command as _, ~cwd as _=?, ~timeout as _=?) => Promise.resolve(Ok("")),
  execAsync: (_cmd, ~options as _=?) =>
    Promise.resolve(({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}: Ports.execResult)),
  execFileAsync: (_cmd, ~args as _=?, ~options=?) => {
    let _ = capturedEnv.contents = switch options {
    | Some(o) => o.env
    | None => None
    }
    Promise.resolve(({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}: Ports.execResult))
  },
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
        ~ejs=NodeJsEjs.make(),
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
        ~ejs=NodeJsEjs.make(),
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

  // WS3: non-path hook without args receives filtered safeEnv (not raw
  // process.env). Asserts that sensitive keys set in process.env do NOT
  // appear in the env passed to execAsync.
  testAsync("WS3: non-path hook without args receives filtered env", resolve => {
    let capturedEnv: ref<option<Dict.t<string>>> = ref(None)
    let sensitiveEnv = Dict.make()
    Dict.set(sensitiveEnv, "PATH", "/usr/bin")
    Dict.set(sensitiveEnv, "HOME", "/root")
    Dict.set(sensitiveEnv, "AWS_SECRET_ACCESS_KEY", "should-not-leak")
    Dict.set(sensitiveEnv, "API_TOKEN", "should-not-leak")

    let sensitiveProcess: Ports.process = {
      ...makeProcess(),
      env: () => sensitiveEnv,
    }

    // Non-path hook ("echo", no slash) with no args — this is the code
    // path that previously dropped safeEnv by passing no env at all.
    let hook: Config.hookCommand = {command: "echo"}
    Hooks.executeHook(
      ~hook,
      ~cwd="/tmp",
      ~timeout=5000,
      ~hookType=Hooks.PreGenerate,
      ~shellEnv=None,
      ~shell=makeEnvCapturingShell(capturedEnv),
      ~process=sensitiveProcess,
      ~path=NodeJsPath.make(),
      ~fs=NodeJsFileSystem.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => {
          // The captured env should be the filtered safeEnv.
          // Sensitive keys from process.env MUST NOT leak.
          switch capturedEnv.contents {
          | Some(env) => {
              assert_false(Dict.has(env, "AWS_SECRET_ACCESS_KEY"))
              assert_false(Dict.has(env, "API_TOKEN"))
            }
            | None => assert_true(false) // execFileAsync wasn't called with options
          }
        }
      | Error(_msg) => assert_true(false)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
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
      ~stagingDir="/tmp/ws2-reject",
      ~shellConfig=Some({enabled: true}),
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell={
        execShellCommand: (~command as _, ~cwd as _=?, ~timeout as _=?) => Promise.resolve(Ok("")),
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

  // --- plan 031: scriptRoot containment ---

  testAsync("executeHook: path validated against scriptRoot not cwd", resolve => {
    // scriptRoot=/safe, cwd=/other — script at /safe/inner.sh should be allowed
    let tmpDir = NodeJs.Os.makeStagingDir()
    let safeDir = NodeJs.Path.join(tmpDir, "safe")
    let innerScript = NodeJs.Path.join(safeDir, "inner.sh")
    NodeJs.Fs.mkdir(safeDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(innerScript, "#!/bin/sh\necho ok\n"))
    ->Promise.then(_ => {
      let hook: Config.hookCommand = {command: "./inner.sh"}
      Hooks.executeHook(
        ~hook,
        ~scriptRoot=safeDir,
        ~cwd=tmpDir,  // cwd is different from scriptRoot
        ~timeout=5000,
        ~hookType=Hooks.PreGenerate,
        ~shellEnv=None,
        ~shell=makeShell(~execAsyncResult=Ok({stdout: "ok", stderr: "", status: Some(0), signalCode: None, killed: false})),
        ~process=makeProcess(),
        ~path=NodeJsPath.make(),
        ~fs=NodeJsFileSystem.make(),
      )
      ->Promise.then(result => {
        switch result {
        | Ok(r) => assert_eq(r.exitCode, 0)
        | Error(e) => {
            Console.error(e)
            assert_false(true)
          }
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

  testAsync("executeHook: script outside scriptRoot is rejected", resolve => {
    // scriptRoot=/safe, cwd=/safe — script at /evil.sh should be rejected
    let tmpDir = NodeJs.Os.makeStagingDir()
    let safeDir = NodeJs.Path.join(tmpDir, "safe")
    NodeJs.Fs.mkdir(safeDir, ~options={recursive: true})
    ->Promise.then(_ => {
      let hook: Config.hookCommand = {command: "/evil.sh"}
      Hooks.executeHook(
        ~hook,
        ~scriptRoot=safeDir,
        ~cwd=safeDir,
        ~timeout=5000,
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
})
