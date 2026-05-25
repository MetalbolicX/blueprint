open TestHelpers

suite("DenoProcess adapter", () => {
  test("implements process operations", () => {
    // Setup Deno mock
    let _ = %raw(`
      globalThis.Deno = {
        cwd: () => "/mock/cwd",
        env: {
          toObject: () => ({ MOCK_ENV: "true" })
        },
        args: ["--force", "my-arg"],
        exit: (code) => { globalThis.__EXIT_CODE = code; }
      }
    `)
    
    let p = DenoProcess.make()
    
    assert_eq(p.cwd(), "/mock/cwd")
    
    let env = p.env()
    assert_eq(Dict.get(env, "MOCK_ENV"), Some("true"))
    
    let argv = p.argv()
    // First two elements are dummy for compat with node process.argv
    assert_eq(Array.get(argv, 0), Some("deno"))
    assert_eq(Array.get(argv, 1), Some("blueprint"))
    assert_eq(Array.get(argv, 2), Some("--force"))
    assert_eq(Array.get(argv, 3), Some("my-arg"))
    
    p.exit(42)
    let exitCode = %raw(`globalThis.__EXIT_CODE`)
    assert_eq(exitCode, 42)
  })
})
