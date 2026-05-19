// EnvInjection_test — environment variable injection security tests

open TestHelpers

suite("EnvInjection", () => {
  test("buildSafeEnv: default env blocks AWS_SECRET_KEY", () => {
    // By default, sensitive env vars should NOT be passed to child processes
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "AWS_SECRET_KEY", "super-secret-value")
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    // Should only have PATH and HOME, not AWS_SECRET_KEY
    assert_false(Dict.has(result, "AWS_SECRET_KEY"))
  })

  test("buildSafeEnv: default env blocks DATABASE_URL", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "DATABASE_URL", "postgresql://user:pass@localhost/db")
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    // DATABASE_URL should not be in safe env
    assert_false(Dict.has(result, "DATABASE_URL"))
  })

  test("buildSafeEnv: default env passes PATH", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    // PATH should be in safe env (safe by default)
    assert_true(Dict.has(result, "PATH"))
  })

  test("buildSafeEnv: default env passes HOME", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    // HOME should be in safe env (safe by default)
    assert_true(Dict.has(result, "HOME"))
  })

  test("buildSafeEnv: explicit env passes MY_CUSTOM_VAR", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")
    Dict.set(inheritedEnv, "MY_CUSTOM_VAR", "custom-value")

    let envConfig: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "MY_CUSTOM_VAR", value: "$MY_CUSTOM_VAR"},
      ],
    }

    let result = EnvFilter.buildSafeEnv(Some(envConfig), inheritedEnv)

    // MY_CUSTOM_VAR should be passed
    assert_true(Dict.has(result, "MY_CUSTOM_VAR"))
  })

  test("buildSafeEnv: explicit env can override PATH", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")

    let envConfig: EnvFilter.shellEnvConfig = {
      vars: [
        {key: "PATH", value: "/custom/path/bin"},
      ],
    }

    let result = EnvFilter.buildSafeEnv(Some(envConfig), inheritedEnv)

    // PATH should be overridden
    switch Dict.get(result, "PATH") {
    | Some(v) => assert_true(String.includes(v, "/custom/path"))
    | None => assert_false(true)
    }
  })

  test("buildSafeEnv: many secret vars are blocked", () => {
    let inheritedEnv = Dict.make()
    Dict.set(inheritedEnv, "AWS_SECRET_KEY", "secret1")
    Dict.set(inheritedEnv, "AWS_ACCESS_KEY_ID", "key123")
    Dict.set(inheritedEnv, "DATABASE_URL", "postgresql://...")
    Dict.set(inheritedEnv, "SECRET_API_KEY", "api-key-123")
    Dict.set(inheritedEnv, "GITHUB_TOKEN", "ghp_token123")
    Dict.set(inheritedEnv, "PATH", "/usr/bin:/bin")
    Dict.set(inheritedEnv, "HOME", "/home/user")

    let result = EnvFilter.buildSafeEnv(None, inheritedEnv)

    // Only PATH and HOME should be present
    assert_true(Dict.has(result, "PATH"))
    assert_true(Dict.has(result, "HOME"))
    assert_false(Dict.has(result, "AWS_SECRET_KEY"))
    assert_false(Dict.has(result, "AWS_ACCESS_KEY_ID"))
    assert_false(Dict.has(result, "DATABASE_URL"))
    assert_false(Dict.has(result, "SECRET_API_KEY"))
    assert_false(Dict.has(result, "GITHUB_TOKEN"))
  })
})