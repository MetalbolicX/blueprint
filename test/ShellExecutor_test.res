// ShellExecutor_test — unit tests for Phase2 ShellExecutor.
// Covers Fetch temp-file cleanup, env-filter config builder, and the three
// execution dispatch branches (ToolCall / InlineCommand / ScriptFile).

open TestHelpers

let rejectError: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)

// ---------- Mocks ----------

let mkExecResult = (~status: int = 0, ~killed: bool = false): Ports.execResult => {
  stdout: "",
  stderr: "",
  status: Some(status),
  signalCode: None,
  killed,
}

let makeShell = (
  ~execAsyncStatus: int = 0,
  ~execAsyncKilled: bool = false,
  ~execFileAsyncStatus: int = 0,
  ~execFileAsyncKilled: bool = false,
): Ports.shell => {
  execAsync: (_cmd, ~options as _=?) =>
    Promise.resolve(mkExecResult(~status=execAsyncStatus, ~killed=execAsyncKilled)),
  execFileAsync: (_cmd, ~args as _=?, ~options as _=?) =>
    Promise.resolve(mkExecResult(~status=execFileAsyncStatus, ~killed=execFileAsyncKilled)),
}

type trackingShell = {
  shell: Ports.shell,
  execFileAsyncCalls: array<string>,
  execAsyncCalls: array<string>,
}

let makeTrackingShell = (): trackingShell => {
  let execFileAsyncCalls: array<string> = []
  let execAsyncCalls: array<string> = []
  let shell: Ports.shell = {
    execAsync: (cmd, ~options as _=?) => {
      let _ = execAsyncCalls->Array.push(cmd)
      Promise.resolve(mkExecResult())
    },
    execFileAsync: (cmd, ~args=?, ~options as _=?) => {
      let _ = execFileAsyncCalls->Array.push(
        cmd ++ "|" ++ (args->Option.getOr([])->Array.join(" ")),
      )
      Promise.resolve(mkExecResult())
    },
  }
  {shell, execFileAsyncCalls, execAsyncCalls}
}

let makeFsWithRmTracking = (): (Ports.fileSystem, ref<array<string>>) => {
  let rmCalls: ref<array<string>> = ref([])
  let base = NodeJsFileSystem.make()
  let fs: Ports.fileSystem = {
    ...base,
    rm: (target, ~options=?) => {
      let _ = rmCalls.contents->Array.push(target)
      base.rm(target, ~options?)
    },
  }
  (fs, rmCalls)
}

let makeFs = (~fileExistsResult: bool = true, ~rmResult: promise<unit> = Promise.resolve()): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()
  {
    ...base,
    fileExists: _ => Promise.resolve(fileExistsResult),
    rm: (_target, ~options as _=?) => rmResult,
  }
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

let path = NodeJsPath.make()

// ---------- cleanupFetchTmpFiles ----------

suite("ShellExecutor fetch staging names", () => {
  testAsync("distinct fetched URLs receive distinct staging filenames", resolve => {
    Fetcher.clearCache()
    let installFetchMock: unit => unit = %raw(`
      function() {
        globalThis.__SHELL_ORIGINAL_FETCH__ = globalThis.fetch;
        globalThis.fetch = async function() {
          return {ok: true, status: 200, statusText: "OK", text: async () => "body"};
        };
      }
    `)
    let restoreFetchMock: unit => unit = %raw(`
      function() { globalThis.fetch = globalThis.__SHELL_ORIGINAL_FETCH__; delete globalThis.__SHELL_ORIGINAL_FETCH__; }
    `)
    installFetchMock()
    let writtenPaths: ref<array<string>> = ref([])
    let base = NodeJsFileSystem.make()
    let fs: Ports.fileSystem = {
      ...base,
      writeFile: (target, content, ~options=?) => {
        let _ = writtenPaths.contents->Array.push(target)
        base.writeFile(target, content, ~options?)
      },
    }
    let stagingDir = NodeJs.Os.makeStagingDir()
    let commands: array<Template.shellCommand> = [
      {target: Template.Fetch("http://8.8.8.8/first"), sourcePath: "first"},
      {target: Template.Fetch("http://8.8.8.8/second"), sourcePath: "second"},
    ]
    ShellExecutor.executeShellCommands(
      ~commands,
      ~cwd=stagingDir,
      ~stagingDir,
      ~shellConfig=None,
      ~fs,
      ~path,
      ~process=makeProcess(),
      ~shell=makeShell(),
    )->Promise.then(result => {
      switch result {
      | Ok(_) => assert_eq(writtenPaths.contents->Array.length, 2)
      | Error(_) => assert_false(true)
      }
      assert_true(writtenPaths.contents[0] != writtenPaths.contents[1])
      restoreFetchMock()
      NodeJs.Fs.rm(stagingDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })->ignore
  })
})

suite("ShellExecutor.cleanupFetchTmpFiles", () => {
  testAsync("empty list resolves without invoking rm", resolve => {
    let (fs, rmCalls) = makeFsWithRmTracking()
    ShellExecutor.cleanupFetchTmpFiles([], ~fs)
    ->Promise.then(_ => {
      assert_eq(rmCalls.contents->Array.length, 0)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("single file calls fs.rm once", resolve => {
    let (fs, rmCalls) = makeFsWithRmTracking()
    ShellExecutor.cleanupFetchTmpFiles(["/tmp/test.tmp"], ~fs)
    ->Promise.then(_ => {
      assert_eq(rmCalls.contents->Array.length, 1)
      assert_eq(rmCalls.contents[0]->Option.getOr(""), "/tmp/test.tmp")
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("multiple files call rm for each entry", resolve => {
    let (fs, rmCalls) = makeFsWithRmTracking()
    ShellExecutor.cleanupFetchTmpFiles(
      ["/tmp/a.tmp", "/tmp/b.tmp", "/tmp/c.tmp"],
      ~fs,
    )
    ->Promise.then(_ => {
      assert_eq(rmCalls.contents->Array.length, 3)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rejected rm is silently swallowed (function still resolves)", resolve => {
    let base = NodeJsFileSystem.make()
    let fs: Ports.fileSystem = {
      ...base,
      rm: (_target, ~options as _=?) => rejectError("EACCES"),
    }
    ShellExecutor.cleanupFetchTmpFiles(["/tmp/bad.tmp"], ~fs)
    ->Promise.then(_ => {
      // Reaching here proves the rejection was swallowed.
      assert_true(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})

// ---------- buildEnvFilterConfig ----------

suite("ShellBuilder.buildEnvFilterConfig", () => {
  test("empty vars yields empty entries array", () => {
    let cfg: EnvFilter.shellEnvConfig = ShellBuilder.buildEnvFilterConfig({vars: Dict.make()})
    assert_eq(cfg.vars->Array.length, 0)
  })

  test("vars dict maps into entries array", () => {
    let cfg: EnvFilter.shellEnvConfig = ShellBuilder.buildEnvFilterConfig({
      vars: Dict.fromArray([("FOO", "bar")]),
    })
    assert_eq(cfg.vars->Array.length, 1)
    assert_eq(cfg.vars[0]->Option.map(e => e.key)->Option.getOr(""), "FOO")
    assert_eq(cfg.vars[0]->Option.map(e => e.value)->Option.getOr(""), "bar")
  })

  test("multiple vars produce multiple entries (length matches input dict)", () => {
    let cfg: EnvFilter.shellEnvConfig = ShellBuilder.buildEnvFilterConfig({
      vars: Dict.fromArray([("A", "1"), ("B", "2"), ("C", "3")]),
    })
    assert_eq(cfg.vars->Array.length, 3)
    // Build a key→value lookup from the entries and verify all originals are present.
    let entriesDict = cfg.vars->Array.reduce(Dict.make(), (acc, e) => {
      Dict.set(acc, e.key, e.value)
      acc
    })
    assert_eq(Dict.get(entriesDict, "A"), Some("1"))
    assert_eq(Dict.get(entriesDict, "B"), Some("2"))
    assert_eq(Dict.get(entriesDict, "C"), Some("3"))
  })
})

// ---------- executeShellCommands — ToolCall ----------

let runShellCommands = (
  ~commands: array<Template.shellCommand>,
  ~shellConfig: option<Config.shellConfig>,
  ~shell: Ports.shell,
  ~fs: Ports.fileSystem = makeFs(),
): promise<result<int, string>> => {
  ShellExecutor.executeShellCommands(
    ~commands,
    ~cwd="/workspace/project",
    ~stagingDir="/workspace/project",
    ~shellConfig,
    ~fs,
    ~path=NodeJsPath.make(),
    ~process=makeProcess(),
    ~shell,
  )
}

suite("ShellExecutor.executeShellCommands — ToolCall", () => {
  testAsync("ToolCall with args routes to execFileAsync with command and args", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "echo",
          toolDef: {
            name: "echo",
            command: "echo",
            args: ["hello", "world"],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true})
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell)
    ->Promise.then(result => {
      assert_eq(tracking.execFileAsyncCalls->Array.length, 1)
      assert_eq(
        tracking.execFileAsyncCalls[0]->Option.getOr(""),
        "echo|hello world",
      )
      switch result {
      | Ok(_) => assert_true(true)
      | Error(_msg) => assert_true(false) // should not error
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("ToolCall ExecFile success increments count", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "echo",
          toolDef: {
            name: "echo",
            command: "echo",
            args: ["hi"],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shell = makeShell(~execFileAsyncStatus=0)
    let shellConfig: option<Config.shellConfig> = Some({enabled: true})
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(count) => assert_eq(count, 1)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("ToolCall ExecFile timeout returns Error mentioning 'timed out'", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "slow",
          toolDef: {
            name: "slow",
            command: "sleep",
            args: ["10"],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shell = makeShell(~execFileAsyncKilled=true)
    let shellConfig: option<Config.shellConfig> = Some({enabled: true})
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "timed out"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("ToolCall ExecFile non-zero exit returns Error with status code", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "fail",
          toolDef: {
            name: "fail",
            command: "false",
            args: [],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shell = makeShell(~execFileAsyncStatus=1)
    let shellConfig: option<Config.shellConfig> = Some({enabled: true})
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => {
          assert_true(String.includes(msg, "exited with code"))
          assert_true(String.includes(msg, "1"))
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("ToolCall no-args + allowlist match routes to execFileAsync", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "ls",
          toolDef: {
            name: "ls",
            command: "ls",
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "ls", command: "ls"}],
    })
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell)
    ->Promise.then(result => {
      assert_eq(tracking.execAsyncCalls->Array.length, 0)
      assert_eq(tracking.execFileAsyncCalls->Array.length, 1)
      assert_eq(tracking.execFileAsyncCalls[0]->Option.getOr(""), "ls|")
      switch result {
      | Ok(count) => assert_eq(count, 1)
      | Error(_msg) => assert_true(false)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("ToolCall with args is rejected when the tool is absent from the allowlist", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "rm",
          toolDef: {
            name: "rm",
            command: "rm",
            args: ["danger"],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "ls", command: "ls"}],
    })
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell)
    ->Promise.then(result => {
      assert_eq(tracking.execAsyncCalls->Array.length, 0)
      assert_eq(tracking.execFileAsyncCalls->Array.length, 0)
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => {
          assert_true(String.includes(msg, "rm"))
          assert_true(String.includes(msg, "tools allowlist"))
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("allowlisted metacharacter ToolCall executes with execFile and never invokes a shell", resolve => {
    let tracking = makeTrackingShell()
    let dangerous = "echo hi; touch pwn"
    let commands: array<Template.shellCommand> = [
      {target: ToolCall({name: "danger", toolDef: {name: "danger", command: dangerous}, sourcePath: "test"}), sourcePath: "test"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true, tools: [{name: "danger", command: dangerous}]})
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell)->Promise.then(result => {
      assert_eq(tracking.execAsyncCalls->Array.length, 0)
      assert_eq(tracking.execFileAsyncCalls, [dangerous ++ "|"])
      switch result {
      | Ok(_) => assert_true(true)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("metacharacter allowlist entry cannot create a shell side effect", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let dangerous = "echo hi; touch pwn"
    let command: Template.shellCommand = {
      target: ToolCall({name: "danger", toolDef: {name: "danger", command: dangerous}, sourcePath: "test"}),
      sourcePath: "test",
    }
    ShellExecutor.executeShellCommands(
      ~commands=[command], ~cwd=tmpDir, ~stagingDir=tmpDir,
      ~shellConfig=Some({enabled: true, tools: [{name: "danger", command: dangerous}]}),
      ~fs=NodeJsFileSystem.make(), ~path=NodeJsPath.make(), ~process=NodeJsProcess.make(),
      ~shell=NodeJsShell.make(),
    )->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(_) => ()
      }
      NodeJs.Fs.fileExists(NodeJs.Path.join(tmpDir, "pwn"))->Promise.then(exists => {
        assert_false(exists)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      })
    })->ignore
  })
})

// ---------- executeShellCommands — error message surfacing ----------

suite("ShellExecutor.executeShellCommands — error message surfacing", () => {
  testAsync("ExecFile rejection surfaces 'execution failed' in error message", resolve => {
    let rejectMsg: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)
    let shell: Ports.shell = {
      ...makeShell(),
      execFileAsync: (_cmd, ~args as _=?, ~options as _=?) => rejectMsg("spawn ENOENT"),
    }
    let commands: array<Template.shellCommand> = [
      {
        target: ToolCall({
          name: "missing",
          toolDef: {
            name: "missing",
            command: "missing-binary",
            args: ["foo"],
          },
          sourcePath: "/src/t.ejs.t",
        }),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true})
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) =>
        assert_true(String.includes(msg, "execution failed"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})

// ---------- executeShellCommands — InlineCommand ----------

suite("ShellExecutor.executeShellCommands — InlineCommand", () => {
  testAsync("shell disabled returns Error mentioning 'disabled'", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: InlineCommand("echo hello"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: false,
      tools: [{name: "echo", command: "echo"}],
    })
    let shell = makeShell()
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "disabled"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("command not in allowlist returns Error mentioning 'tools allowlist'", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: InlineCommand("rm -rf /"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "echo", command: "echo"}],
    })
    let shell = makeShell()
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => {
          assert_true(String.includes(msg, "not in tools allowlist"))
          assert_true(String.includes(msg, "rm -rf /"))
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rejects trailing shell operators after an allowlisted command", resolve => {
    let commands: array<Template.shellCommand> = [
      {target: InlineCommand("git status && curl evil"), sourcePath: "/src/t.ejs.t"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true, tools: [{name: "git", command: "git"}]})
    runShellCommands(~commands, ~shellConfig, ~shell=makeShell())
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "tools allowlist"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runs whitespace-separated args with execFile", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {target: InlineCommand("git status"), sourcePath: "/src/t.ejs.t"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true, tools: [{name: "git", command: "git"}]})
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell)
    ->Promise.then(result => {
      assert_eq(tracking.execFileAsyncCalls->Array.length, 1)
      assert_eq(tracking.execFileAsyncCalls[0]->Option.getOr(""), "git|status")
      switch result {
      | Ok(_) => assert_true(true)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rejects command when first token is not allowlisted", resolve => {
    let commands: array<Template.shellCommand> = [
      {target: InlineCommand("git status"), sourcePath: "/src/t.ejs.t"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true, tools: [{name: "eslint", command: "eslint"}]})
    runShellCommands(~commands, ~shellConfig, ~shell=makeShell())
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "tools allowlist"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rejects quoted inline arguments", resolve => {
    let commands: array<Template.shellCommand> = [
      {target: InlineCommand("echo \"a b\""), sourcePath: "/src/t.ejs.t"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({enabled: true, tools: [{name: "echo", command: "echo"}]})
    runShellCommands(~commands, ~shellConfig, ~shell=makeShell())
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "tools allowlist"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("command path outside project tree returns Error mentioning 'outside project tree'", resolve => {
    // /bin/ls is absolute and outside /workspace/project.
    let commands: array<Template.shellCommand> = [
      {
        target: InlineCommand("/bin/ls"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "/bin/ls", command: "/bin/ls"}],
    })
    let shell = makeShell()
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "outside project tree"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("successful execution increments count and returns Ok", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {
        target: InlineCommand("echo hello"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "echo", command: "echo"}],
    })
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell)
    ->Promise.then(result => {
      switch result {
      | Ok(count) => assert_eq(count, 1)
      | Error(_msg) => assert_true(false) // should not error
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("execFile failure surfaces as an execution error", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: InlineCommand("echo hi"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "echo", command: "echo"}],
    })
    let shell = makeShell(~execFileAsyncStatus=1)
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => {
           assert_true(String.includes(msg, "exited with code"))
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("executeShellCommands resolves Error when execFile port rejects", resolve => {
    let commands: array<Template.shellCommand> = [
      {target: InlineCommand("echo hi"), sourcePath: "/src/t.ejs.t"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "echo", command: "echo"}],
    })
    let shell: Ports.shell = {
      ...makeShell(),
      execFileAsync: (_cmd, ~args as _=?, ~options as _=?) => rejectError("port exploded"),
    }
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(message) => assert_true(String.includes(message, "port exploded"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("inline command passes ExecPolicy timeout to execFileAsync", resolve => {
    let timeoutSeen: ref<option<int>> = ref(None)
    let shell: Ports.shell = {
      execAsync: (_cmd, ~options as _=?) => Promise.resolve(mkExecResult()),
      execFileAsync: (_cmd, ~args as _=?, ~options=?) => {
        timeoutSeen.contents = options->Option.flatMap(opts => opts.timeout)
        Promise.resolve(mkExecResult())
      },
    }
    let commands: array<Template.shellCommand> = [
      {target: InlineCommand("echo hi"), sourcePath: "/src/t.ejs.t"},
    ]
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "echo", command: "echo"}],
    })
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(count) => assert_eq(count, 1)
      | Error(_) => assert_false(true)
      }
      assert_eq(timeoutSeen.contents, Some(ExecPolicy.defaultTimeout))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})

// ---------- executeShellCommands — ScriptFile ----------

suite("ShellExecutor.executeShellCommands — ScriptFile", () => {
  testAsync("script path outside project tree returns Error", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: ScriptFile("/tmp/evil-script.sh"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = None
    let shell = makeShell()
    runShellCommands(~commands, ~shellConfig, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Script path outside project tree"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("script file does not exist returns Error mentioning 'not found'", resolve => {
    // Path stays inside cwd → passes security; fileExists returns false → fails.
    let commands: array<Template.shellCommand> = [
      {
        target: ScriptFile("/workspace/project/missing.sh"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = None
    let fs = makeFs(~fileExistsResult=false)
    let shell = makeShell()
    runShellCommands(~commands, ~shellConfig, ~fs, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Script file not found"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("successful execution calls execFileAsync with resolved path and increments count", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {
        target: ScriptFile("/workspace/project/scripts/setup.sh"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = None
    let fs = makeFs(~fileExistsResult=true)
    runShellCommands(~commands, ~shellConfig, ~shell=tracking.shell, ~fs)
    ->Promise.then(result => {
      assert_eq(tracking.execFileAsyncCalls->Array.length, 1)
      assert_eq(
        tracking.execFileAsyncCalls[0]->Option.getOr(""),
        "/workspace/project/scripts/setup.sh|",
      )
      switch result {
      | Ok(count) => assert_eq(count, 1)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("script command resolves relative to project cwd", resolve => {
    let tracking = makeTrackingShell()
    let commands: array<Template.shellCommand> = [
      {target: ScriptFile("scripts/run.sh"), sourcePath: "/src/t.ejs.t"},
    ]
    let cwd = "/workspace/project"
    let fs = makeFs(~fileExistsResult=true)
    ShellExecutor.executeShellCommands(
      ~commands,
      ~cwd,
      ~stagingDir=cwd,
      ~shellConfig=None,
      ~fs,
      ~path,
      ~process=makeProcess(),
      ~shell=tracking.shell,
    )
    ->Promise.then(_ => {
      assert_true(String.startsWith(tracking.execFileAsyncCalls[0]->Option.getOr(""), cwd ++ "/"))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("script timeout returns Error mentioning 'timed out'", resolve => {
    let commands: array<Template.shellCommand> = [
      {
        target: ScriptFile("/workspace/project/scripts/long.sh"),
        sourcePath: "/src/t.ejs.t",
      },
    ]
    let shellConfig: option<Config.shellConfig> = None
    let fs = makeFs(~fileExistsResult=true)
    let shell = makeShell(~execFileAsyncKilled=true)
    runShellCommands(~commands, ~shellConfig, ~fs, ~shell)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "timed out"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
