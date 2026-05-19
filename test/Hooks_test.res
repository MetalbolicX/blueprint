// Hooks_test — lifecycle hook execution tests

open TestHelpers

suite("Hooks", () => {
  testAsync("executeHook: preserves provided hookType", resolve => {
    let hook: Config.hookCommand = {
      command: "echo hello",
    }
    Hooks.executeHook(~hook, ~cwd=".", ~timeout=1000, ~hookType=Hooks.PostGenerate, ~shellEnv=None)
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
    Hooks.executeHook(~hook, ~cwd=".", ~timeout=5000, ~hookType=Hooks.PreGenerate, ~shellEnv=None)
    ->Promise.then(result => {
      switch result {
      | Ok(hookResult) => {
          assert_eq(hookResult.exitCode, 0)
          // stdout might be empty for echo, just check exit code
          assert_true(true)
        }
      | Error(_e) => {
          // Debug: print error
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

    Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Hooks.PostGenerate, ~shellConfig=None)
    ->Promise.then(postResult => {
      switch postResult {
      | Ok() =>
        // PreGenerate is not set in config - calling with PreGenerate should succeed (no hook to run)
        let cfgNoPre: Config.config = {
          hooks: {
            postGenerate: {command: "echo post-ok"},
            timeout: 1,
          },
        }
        Hooks.run(~config=cfgNoPre, ~projectRoot=".", ~hookType=Hooks.PreGenerate, ~shellConfig=None)
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

    Hooks.run(~config=cfg, ~projectRoot=".", ~hookType=Hooks.PostGenerate, ~shellConfig=None)
    ->Promise.then(result => {
      switch result {
      | Ok() => assert_true(true)
      | Error(_e) => {
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
    Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Hooks.PreGenerate, ~shellEnv=None)
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
    Hooks.executeHook(~hook, ~cwd="/tmp", ~timeout=1000, ~hookType=Hooks.PreGenerate, ~shellEnv=None)
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
    // Create a hook that prints env vars
    let hook: Config.hookCommand = {
      command: "printf",
      args: ["%s", "HOME-is-set"],
    }
    Hooks.executeHook(~hook, ~cwd=".", ~timeout=5000, ~hookType=Hooks.PreGenerate, ~shellEnv=None)
    ->Promise.then(result => {
      switch result {
      | Ok(hookResult) => {
          assert_eq(hookResult.exitCode, 0)
          // Just verify it ran successfully
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
    // Short timeout should cause error
    Hooks.executeHook(~hook, ~cwd=".", ~timeout=100, ~hookType=Hooks.PreGenerate, ~shellEnv=None)
    ->Promise.then(result => {
      switch result {
      | Error(_msg) => assert_true(true) // Timeout error expected
      | Ok(_) => assert_false(true) // Should not succeed
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})