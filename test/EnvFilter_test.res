// EnvFilter_test — unit tests for environment variable filtering

open TestHelpers

suite("EnvFilter", () => {
  test("buildSafeEnv: empty config returns only PATH and HOME", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("SECRET", "my-secret"),
      ("API_KEY", "abc123"),
    ])
    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)
    assert_eq(Dict.get(result, "PATH"), Some("/usr/bin"))
    assert_eq(Dict.get(result, "HOME"), Some("/home/user"))
    assert_eq(Dict.get(result, "SECRET"), None)
    assert_eq(Dict.get(result, "API_KEY"), None)
  })

  test("buildSafeEnv: add custom var includes PATH, HOME and custom", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("SECRET", "my-secret"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "CUSTOM_VAR", value: "custom-value"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    assert_eq(Dict.get(result, "PATH"), Some("/usr/bin"))
    assert_eq(Dict.get(result, "HOME"), Some("/home/user"))
    assert_eq(Dict.get(result, "CUSTOM_VAR"), Some("custom-value"))
    assert_eq(Dict.get(result, "SECRET"), None)
  })

  test("buildSafeEnv: override PATH uses override value", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "PATH", value: "/custom/bin"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    assert_eq(Dict.get(result, "PATH"), Some("/custom/bin"))
    assert_eq(Dict.get(result, "HOME"), Some("/home/user"))
  })

  test("buildSafeEnv: sensitive var not in config is excluded", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("AWS_SECRET", "secret-value"),
      ("DATABASE_URL", "postgres://..."),
    ])
    // No shell.env config at all
    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)
    assert_eq(Dict.get(result, "PATH"), Some("/usr/bin"))
    assert_eq(Dict.get(result, "HOME"), Some("/home/user"))
    assert_eq(Dict.get(result, "AWS_SECRET"), None)
    assert_eq(Dict.get(result, "DATABASE_URL"), None)
  })

  test("buildSafeEnv: inherit syntax references inherited var", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("API_KEY", "my-api-key"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "MY_API_KEY", value: "$API_KEY"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    assert_eq(Dict.get(result, "MY_API_KEY"), Some("my-api-key"))
  })

  test("buildSafeEnv: multiple vars from config", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("VAR1", "val1"),
      ("VAR2", "val2"),
      ("VAR3", "val3"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "KEEP1", value: "explicit1"},
        {key: "KEEP2", value: "explicit2"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    assert_eq(Dict.get(result, "PATH"), Some("/usr/bin"))
    assert_eq(Dict.get(result, "HOME"), Some("/home/user"))
    assert_eq(Dict.get(result, "KEEP1"), Some("explicit1"))
    assert_eq(Dict.get(result, "KEEP2"), Some("explicit2"))
    assert_eq(Dict.get(result, "VAR1"), None)
    assert_eq(Dict.get(result, "VAR2"), None)
    assert_eq(Dict.get(result, "VAR3"), None)
  })

  // ---------- WS4: ${...} parameter expansion rejected ----------

  test("WS4: var value containing \${VAR} is rejected and not in env", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("SECRET", "actual-secret"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "LEAK_VAR", value: "${SECRET}"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    // The dangerous value is filtered out — SECRET value never reaches the
    // child process, and LEAK_VAR isn't set at all.
    assert_eq(Dict.get(result, "LEAK_VAR"), None)
    assert_eq(Dict.get(result, "SECRET"), None)
  })

  test("WS4: var value with inline \${...} (not at start) is also rejected", () => {
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("SECRET", "actual-secret"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "INLINE_LEAK", value: "/safe/prefix/${SECRET}/suffix"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    assert_eq(Dict.get(result, "INLINE_LEAK"), None)
  })

  test("WS4: bare $VAR reference (existing behavior) still works", () => {
    // Negative control: the bare-dollar syntax that resolveValue already
    // handles must continue to pass through, so we don't regress.
    let inheritedEnv = Dict.fromArray([
      ("PATH", "/usr/bin"),
      ("HOME", "/home/user"),
      ("API_KEY", "my-api-key"),
    ])
    let shellEnv: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "MY_API_KEY", value: "$API_KEY"},
      ],
    }
    let result = EnvFilter.buildSafeEnv(Some(shellEnv), inheritedEnv)
    assert_eq(Dict.get(result, "MY_API_KEY"), Some("my-api-key"))
  })
})