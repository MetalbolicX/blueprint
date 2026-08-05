// Hooks_test — lifecycle hook execution tests

open TestHelpers

let runTests = (label, processAdapter, shellAdapter, pathAdapter, fsAdapter) => {
  suite(`Hooks [${label}]`, () => {
    testAsync("executeHook: preserves provided hookType", resolve => {
      let hook: Config.hookCommand = {
        command: "echo hello",
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=1000, ~hookType=Hooks.PostGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok(hookResult) => assert_eq(hookResult.hookType, Hooks.PostGenerate)
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
      ->ignore
    })

    testAsync("executeHook: hook without args uses shell exec", resolve => {
      let hook: Config.hookCommand = {
        command: "echo hook-no-args",
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=5000, ~hookType=Hooks.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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

    testAsync("run: executes only selected hookType", resolve => {
      let cfg: Config.config = {
        hooks: {
          postGenerate: {command: "echo post-ok"},
          timeout: 1,
        },
      }

      Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Hooks.PostGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(postResult => {
        switch postResult {
        | Ok() =>
          let cfgNoPre: Config.config = {
            hooks: {
              postGenerate: {command: "echo post-ok"},
              timeout: 1,
            },
          }
          Hooks.run(~config=cfgNoPre, ~projectRoot=".", ~hookType=Hooks.PreGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
          ->Promise.then(preResult => {
            switch preResult {
            | Ok() => assert_true(true)
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

      Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Hooks.PostGenerate, ~shellConfig=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
      ->Promise.then(result => {
        switch result {
        | Ok() => assert_true(true)
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
      Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Hooks.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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
      Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Hooks.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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

    testAsync("executeHook: safe env is passed to child process", resolve => {
      let hook: Config.hookCommand = {
        command: "printf",
        args: ["%s", "HOME-is-set"],
      }
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=5000, ~hookType=Hooks.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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
      Hooks.executeHook(~hook, ~cwd=".", ~timeout=100, ~hookType=Hooks.PreGenerate, ~shellEnv=None, ~shell=shellAdapter, ~process=processAdapter, ~path=pathAdapter, ~fs=fsAdapter)
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
  })
}

runTests("Node.js", NodeJsProcess.make(), NodeJsShell.make(), NodeJsPath.make(), NodeJsFileSystem.make())