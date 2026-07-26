// TemplateRenderer_test — unit tests for TemplateRenderer error propagation

open TestHelpers

suite("TemplateRenderer.resolveTargetPath — error propagation", () => {
  let ejs = NodeJsEjs.make()

  test("EJS error in to: path surfaces (not 'No 'to' directive found')", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )
    // Template expression references an undefined EJS variable — EJS throws.
    let result = TemplateRenderer.resolveTargetPath(~ejs, Template.To("src/<%= undefined_var %>.tsx"), ctx)
    switch result {
    | Error(msg) =>
      // EJS error message format is unstable across versions; downgrade to
      // asserting the error does NOT contain the misleading "No 'to' directive found".
      assert_false(String.includes(msg, "No 'to' directive found"))
    | Ok(_) => assert_false(true) // should error
    }
  })

  test("valid to: path resolves successfully", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )
    let result = TemplateRenderer.resolveTargetPath(~ejs, Template.To("src/<%= Name %>.tsx"), ctx)
    switch result {
    | Ok(path) => assert_eq(path, "src/Hello.tsx")
    | Error(_) => assert_false(true) // should not error
    }
  })
})
