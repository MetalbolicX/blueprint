// ExecPolicy_test — unit tests for the ExecPolicy decision module.
// Asserts the three decision branches (ExecFile / ShellExact / Reject) plus
// the WS2 default timeout constant.

open TestHelpers

suite("ExecPolicy", () => {
  test("defaultTimeout: is the spec-locked 30s", () => {
    assert_eq(ExecPolicy.defaultTimeout, 30000)
  })

  test("decide: args present → ExecFile (no shell interpretation)", () => {
    switch ExecPolicy.decide(~command="npm", ~args=Some(["install", "--save-dev"]), ~allowlist=[]) {
    | ExecFile(cmd, args) => {
        assert_eq(cmd, "npm")
        assert_eq(args->Array.length, 2)
        assert_eq(args[0]->Option.getOr(""), "install")
        assert_eq(args[1]->Option.getOr(""), "--save-dev")
      }
    | ShellExact(_) => assert_false(true)
    | Reject(_) => assert_false(true)
    }
  })

  test("decide: args present overrides allowlist (ExecFile always wins on args)", () => {
    // args present means we go through ExecFile regardless of allowlist membership.
    switch ExecPolicy.decide(~command="whatever", ~args=Some(["x"]), ~allowlist=["whatever", "other"]) {
    | ExecFile(cmd, args) => {
        assert_eq(cmd, "whatever")
        assert_eq(args->Array.length, 1)
      }
    | ShellExact(_) => assert_false(true)
    | Reject(_) => assert_false(true)
    }
  })

  test("decide: no args + allowlist match → ShellExact", () => {
    switch ExecPolicy.decide(~command="eslint", ~args=None, ~allowlist=["eslint", "prettier"]) {
    | ShellExact(cmd) => assert_eq(cmd, "eslint")
    | ExecFile(_, _) => assert_false(true)
    | Reject(_) => assert_false(true)
    }
  })

  test("decide: no args + exact case-sensitive match required", () => {
    switch ExecPolicy.decide(~command="ESLINT", ~args=None, ~allowlist=["eslint"]) {
    | Reject(reason) => assert_true(String.includes(reason, "ESLINT"))
    | _ => assert_false(true)
    }
  })

  test("decide: no args + absent from allowlist → Reject with diagnostic", () => {
    switch ExecPolicy.decide(~command="rm", ~args=None, ~allowlist=["eslint", "prettier"]) {
    | Reject(reason) => {
        assert_true(String.includes(reason, "rm"))
        assert_true(String.includes(reason, "tools allowlist"))
      }
    | _ => assert_false(true)
    }
  })

  test("decide: empty allowlist + no args → Reject (never opens shell by default)", () => {
    switch ExecPolicy.decide(~command="echo", ~args=None, ~allowlist=[]) {
    | Reject(reason) => assert_true(String.includes(reason, "echo"))
    | _ => assert_false(true)
    }
  })

  test("decide: empty allowlist + args → still ExecFile (allowlist only gates no-args shell)", () => {
    switch ExecPolicy.decide(~command="echo", ~args=Some(["hello"]), ~allowlist=[]) {
    | ExecFile(cmd, args) => {
        assert_eq(cmd, "echo")
        assert_eq(args->Array.length, 1)
      }
    | _ => assert_false(true)
    }
  })
})
