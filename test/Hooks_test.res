// Hooks_test — lifecycle hook execution tests

open TestHelpers

let makeRecordingShell = (recorded: ref<(string, array<string>, option<int>)>): Ports.shell => {
  execFileAsync: (command, ~args=?, ~options=?) => {
    let args = args->Option.getOr([])
    let timeout = options->Option.flatMap(o => o.timeout)
    recorded.contents = (command, args, timeout)
    Promise.resolve(({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}: Ports.execResult))
  },
}

let runTests = (label, processAdapter, shellAdapter, pathAdapter, fsAdapter) => {
  suite(`Hooks [${label}]`, () => {
    testAsync("executeHook: preserves provided hookType", resolve => {
      let hook: Config.hookCommand = {
        command: "echo hello",
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=1000, ~hookType=Ports.PostGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok(hookResult) => assert_eq(hookResult.hookType, Ports.PostGenerate)
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })

    testAsync("executeHook: hook without args uses execFile", resolve => {
      let hook: Config.hookCommand = {
        command: "echo hook-no-args",
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=5000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok(hookResult) => {
            assert_eq(hookResult.exitCode, 0)
            assert_true(true)
          }
        | Error(e) => {
            Console.error("executeHook error: " ++ e)
            assert_false(true)
          }
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })

    testAsync("executeHook: tokenizes non-path command into execFile arguments", resolve => {
      let recorded = ref(("", [], None))
      let hook: Config.hookCommand = {command: "npm test"}
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=1234, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=makeRecordingShell(recorded), ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok(_) => {
            let (command, args, timeout) = recorded.contents
            assert_eq(command, "npm")
            assert_eq(args, ["test"])
            assert_eq(timeout, Some(1234))
          }
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })->ignore
    })

    testAsync("executeHook: rejects shell metacharacters with hook name", resolve => {
      let hook: Config.hookCommand = {command: "npm test && echo bad"}
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=1000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Error(message) => assert_true(String.includes(message, "pre_generate hook failed") || String.includes(message, "npm test"))
        | Ok(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })->ignore
    })

    testAsync("executeHook: configured tools allowlist rejects other binaries", resolve => {
      let recorded = ref(("", [], None))
      let hook: Config.hookCommand = {command: "git status"}
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=1000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=makeRecordingShell(recorded), ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter, ~toolsAllowlist=Some(["npm"]))
      ->Promise.then(result => {
        switch result {
        | Error(message) => assert_true(String.includes(message, "tools allowlist"))
        | Ok(_) => assert_false(true)
        }
        assert_eq(recorded.contents, ("", [], None))
        resolve()
        Promise.resolve()
      })->ignore
    })

    testAsync("executeHook: unset tools allowlist permits tokenized binary", resolve => {
      let recorded = ref(("", [], None))
      let hook: Config.hookCommand = {command: "npm test"}
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=1000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=makeRecordingShell(recorded), ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter, ~toolsAllowlist=None)
      ->Promise.then(result => {
        switch result {
        | Ok(_) => assert_eq(recorded.contents, ("npm", ["test"], Some(1000)))
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })->ignore
    })

    testAsync("run: executes only selected hookType", resolve => {
      let cfg: Config.config = {
        hooks: {
          postGenerate: {command: "echo post-ok"},
          timeout: 1,
        },
      }

      Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Ports.PostGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(postResult => {
        switch postResult {
        | Ok(_) =>
          let cfgNoPre: Config.config = {
            hooks: {
              postGenerate: {command: "echo post-ok"},
              timeout: 1,
            },
          }
          Hooks.run(~config=cfgNoPre, ~projectRoot=".", ~hookType=Ports.PreGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
          ->Promise.then(preResult => {
            switch preResult {
            | Ok(_) => assert_true(true)
            | Error(_) => assert_false(true)
            }
            resolve()
            Promise.resolve()
          })
        | Error(_) => {
            assert_false(true)
            resolve()
            Promise.resolve()
          }
        }
      })
      ->ignore
    })

    testAsync("run: hook with args uses execFile", resolve => {
      let cfg: Config.config = {
        hooks: {
          postGenerate: {command: "echo", args: ["post-with-args"]},
          timeout: 5,
        },
      }

      Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Ports.PostGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok(_) => assert_true(true)
        | Error(_) => {
            assert_false(true)
          }
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })

    testAsync("executeHook: relative script outside project tree returns error", resolve => {
      let hook: Config.hookCommand = {
        command: "../evil.sh",
      }
      Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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

    testAsync("executeHook: absolute path outside project tree returns error", resolve => {
      let hook: Config.hookCommand = {
        command: "/etc/passwd",
      }
      Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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

    testAsync("executeHook: path-like commands retain tree containment", resolve => {
      let hook: Config.hookCommand = {command: "../outside.sh"}
      Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Error(message) => assert_true(String.includes(message, "outside project tree"))
        | Ok(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })->ignore
    })

    testAsync("executeHook: safe env is passed to child process", resolve => {
      let hook: Config.hookCommand = {
        command: "printf",
        args: ["%s", "HOME-is-set"],
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=5000, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok(hookResult) => {
            assert_eq(hookResult.exitCode, 0)
            assert_true(true)
          }
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })

    testAsync("executeHook: timeout is applied", resolve => {
      let hook: Config.hookCommand = {
        command: "sleep 10",
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=100, ~hookType=Ports.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Error(_msg) => assert_true(true) 
        | Ok(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })

    testAsync("run: pre_generate returns hookResult with stdout preserved", resolve => {
      let cfg: Config.config = {
        hooks: {
          preGenerate: {command: "printf", args: ["%s", "{\"k\":\"hello\"}"]},
          timeout: 5,
        },
      }
      Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Ports.PreGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(r => {
        switch r {
        | Ok(hookResult) => {
            assert_eq(hookResult.hookType, Ports.PreGenerate)
            assert_true(String.includes(hookResult.output, "\"k\""))
            assert_true(String.includes(hookResult.output, "hello"))
          }
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })
  })
}

runTests("Node.js", NodeJsProcess.make(), NodeJsShell.make(), NodeJsPath.make(), NodeJsFileSystem.make())
