// Hooks_test — lifecycle hook execution tests

open TestHelpers

suite("Hooks", () => {
  test("parseCommand: splits interpreter and args", () => {
    let (interpreter, args) = Hooks.parseCommand("bash scripts/validate.sh")
    assert_eq(interpreter, "bash")
    assert_eq(args, "scripts/validate.sh")
  })

  testAsync("executeHook: preserves provided hookType", resolve => {
    Hooks.executeHook(~command="echo hello", ~cwd=".", ~timeout=1000, ~hookType=Hooks.PostGenerate)
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

  testAsync("run: executes only selected hookType", resolve => {
    let cfg: Config.config = {
      hooks: {
        preGenerate: "false",
        postGenerate: "echo post-ok",
        timeout: 1,
      },
    }

    Hooks.run(~config=cfg, ~cwd=".", ~hookType=Hooks.PostGenerate)
    ->Promise.then(postResult => {
      switch postResult {
      | Ok() =>
        Hooks.run(~config=cfg, ~cwd=".", ~hookType=Hooks.PreGenerate)
        ->Promise.then(preResult => {
          switch preResult {
          | Error(_) => assert_true(true)
          | Ok() => assert_false(true)
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
})
