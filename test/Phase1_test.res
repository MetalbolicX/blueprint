// Phase1_test — staging and rendering tests

open TestHelpers

suite("Phase1", () => {
  test("phase1Result: structure", () => {
    let result = {
      Phase1.stagingDir: "/tmp/fluxo-abc123",
      renderedFiles: [("/src/Hello.tsx.ejs.t", "src/Hello.tsx")],
      shellCommands: [],
    }

    assert_eq(result.stagingDir, "/tmp/fluxo-abc123")
    assert_eq(Array.length(result.renderedFiles), 1)
  })

  test("phase1Error: structure", () => {
    let err = {
      Phase1.stagingDir: "/tmp/fluxo-abc123",
      message: "Failed to render",
    }

    assert_eq(err.stagingDir, "/tmp/fluxo-abc123")
    assert_eq(err.message, "Failed to render")
  })

  test("resolveTargetPath: resolves to directive", () => {
    let _nv = Context.makeNameVariants("Hello")
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.To("src/{{ .Name }}.tsx"), ctx)
    switch result {
    | Some(path) => assert_eq(path, "src/Hello.tsx")
    | None => assert_false(true)
    }
  })

  test("resolveTargetPath: non-To directive returns None", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.Sh("npm install"), ctx)
    switch result {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })

  test("resolveTargetPath: EJS path renders correctly", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.To("src/<%= name %>.tsx"), ctx)
    switch result {
    | Some(path) => assert_eq(path, "src/button.tsx")
    | None => assert_false(true)
    }
  })
})