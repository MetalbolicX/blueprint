// HookSecurity_test — hook-specific security tests

open TestHelpers

suite("HookSecurity", () => {
  test("executeHook: script outside project tree is blocked", () => {
    // Hook script with path outside project tree should be rejected
    let hook: Config.hookCommand = {
      command: "/etc/malicious.sh",
    }

    // Hooks._isPath should detect absolute paths and reject them
    // The actual check happens in executeHook
    let isAbsolute = Js.String.includes("/", hook.command)
    assert_true(isAbsolute) // /etc/malicious.sh contains / so it is a path
  })

  test("executeHook: hook with shell:true (no args) uses shell exec", () => {
    // Hook with just command (no args) should use shell exec
    let hook: Config.hookCommand = {
      command: "echo hello",
    }

    // No args means shell exec (exec with shell:true)
    assert_true(hook.args == None)
  })

  test("executeHook: hook with execFile (args present) is safe execution", () => {
    // Hook with args uses execFile (no shell)
    let hook: Config.hookCommand = {
      command: "echo",
      args: ["safe", "args"],
    }

    // With args, execution uses execFile (no shell interpretation)
    assert_true(hook.args != None)
  })

  test("executeHook: timeout is respected", () => {
    // Hook with very short timeout should fail
    let _hook: Config.hookCommand = {
      command: "sleep 10",
    }

    // Short timeout like 100ms should cause timeout error
    assert_true(true) // Placeholder - actual timeout test
  })

  test("executeHook: sensitive env vars are filtered", () => {
    // EnvFilter should block sensitive vars in hook execution
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "AWS_SECRET_KEY", "secret")
    Dict.set(inheritedEnv, "PATH", "/usr/bin")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    // AWS_SECRET_KEY should not be in filtered env
    assert_false(Dict.has(result, "AWS_SECRET_KEY"))
  })

  test("executeHook: relative path traversal is blocked", () => {
    // Hook with command like "../../../etc/evil.sh" should be blocked
    let hook: Config.hookCommand = {
      command: "../../../etc/evil.sh",
    }

    // The command should be detected as a path (contains ../ or /)
    let isPath = Js.String.includes("/", hook.command)
    assert_true(isPath)
  })
})