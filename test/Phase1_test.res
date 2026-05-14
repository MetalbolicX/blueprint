// Phase1_test — staging and rendering tests

suite("Phase1", () => {
  test("phase1Result: structure", () => {
    let result = {
      Phases.Phase1.stagingDir: "/tmp/fluxo-abc123",
      renderedFiles: [("/src/Hello.tsx.ejs.t", "src/Hello.tsx")],
      shellCommands: [],
    }

    assert_eq(result.stagingDir, "/tmp/fluxo-abc123")
    assert_eq(Js.Array.length(result.renderedFiles), 1)
  })

  test("phase1Error: structure", () => {
    let err = {
      Phases.Phase1.stagingDir: "/tmp/fluxo-abc123",
      message: "Failed to render",
    }

    assert_eq(err.stagingDir, "/tmp/fluxo-abc123")
    assert_eq(err.message, "Failed to render")
  })

  test("resolveTargetPath: resolves to directive", () => {
    let nv = Context.makeNameVariants("Hello")
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )

    let result = Phases.Phase1.resolveTargetPath(Template.To("src/{{ .Name }}.tsx"), ctx)
    switch result {
    | Some(path) => assert_eq(path, "src/Hello.tsx")
    | None => assert_false(true)
    }
  })
})