// ExecPolicy_test — unit tests for the ExecPolicy decision module.
// Asserts the ExecFile and Reject decision branches plus
// the WS2 default timeout constant.

open TestHelpers

suite("ExecPolicy", () => {
  test("defaultTimeout: is the spec-locked 30s", () => {
    assert_eq(ExecPolicy.defaultTimeout, 30000)
  })

  test("decide: args present still require allowlist membership", () => {
    switch ExecPolicy.decide(~command="npm", ~args=Some(["install", "--save-dev"]), ~allowlist=[]) {
    | Reject(reason) => assert_true(String.includes(reason, "tools allowlist"))
    | _ => assert_false(true)
    }
  })

  test("decide: args require allowlist membership and use ExecFile", () => {
    switch ExecPolicy.decide(~command="whatever", ~args=Some(["x"]), ~allowlist=["whatever", "other"]) {
    | ExecFile(cmd, args) => {
        assert_eq(cmd, "whatever")
        assert_eq(args->Array.length, 1)
      }
    | Reject(_) => assert_false(true)
    }
  })

  test("decide: args absent from allowlist are rejected", () => {
    switch ExecPolicy.decide(~command="whatever", ~args=Some(["x"]), ~allowlist=[]) {
    | Reject(reason) => assert_true(String.includes(reason, "tools allowlist"))
    | _ => assert_false(true)
    }
  })

  test("decide: allowlisted metacharacter command is ExecFile", () => {
    let command = "echo hi; touch pwn"
    switch ExecPolicy.decide(~command, ~args=None, ~allowlist=[command]) {
    | ExecFile(actual, args) => {
        assert_eq(actual, command)
        assert_eq(args, [])
      }
    | _ => assert_false(true)
    }
  })

  test("decide: no args + allowlist match → ExecFile", () => {
    switch ExecPolicy.decide(~command="eslint", ~args=None, ~allowlist=["eslint", "prettier"]) {
    | ExecFile(cmd, args) => {
        assert_eq(cmd, "eslint")
        assert_eq(args, [])
      }
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

  test("decide: empty allowlist denies args too", () => {
    switch ExecPolicy.decide(~command="echo", ~args=Some(["hello"]), ~allowlist=[]) {
    | Reject(_) => assert_true(true)
    | _ => assert_false(true)
    }
  })
})
