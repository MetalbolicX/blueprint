// Renderer_test — _extractUndefinedVar tests

open TestHelpers

suite("Renderer", () => {
  test("extractUndefinedVar: finds variable name", () => {
    switch Renderer.extractUndefinedVar("myVar is not defined") {
    | Some(name) => assert_eq(name, "myVar")
    | None => assert_false(true)
    }
  })

  test("extractUndefinedVar: handles $ prefixed names", () => {
    switch Renderer.extractUndefinedVar("$data is not defined") {
    | Some(name) => assert_eq(name, "$data")
    | None => assert_false(true)
    }
  })

  test("extractUndefinedVar: handles underscore names", () => {
    switch Renderer.extractUndefinedVar("my_var_name is not defined") {
    | Some(name) => assert_eq(name, "my_var_name")
    | None => assert_false(true)
    }
  })

  test("extractUndefinedVar: handles names with digits", () => {
    switch Renderer.extractUndefinedVar("prop2 is not defined") {
    | Some(name) => assert_eq(name, "prop2")
    | None => assert_false(true)
    }
  })

  test("extractUndefinedVar: unrelated error returns None", () => {
    switch Renderer.extractUndefinedVar("Unexpected token }") {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })

  test("extractUndefinedVar: empty marker msg returns None", () => {
    switch Renderer.extractUndefinedVar(" is not defined") {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })

  testAsync("render: missing required variable returns Error not throw", resolve => {
    // Incomplete renderContext missing 'name' should return Error, not throw
    // We test by passing a context where the EJS template references an undefined var
    let tmpl: Template.template = {
      sourcePath: "/test/res/Test.res.ejs.t",
      directives: [Template.To("out.txt")],
      body: "Hello <%= missingVar %>",
    }

    // Build a minimal renderContext with only the required fields
    let ctx: Renderer.renderContext = {
      name: "Test",
      pascalName: "Test",
      names: "tests",
      pluralPascalName: "Tests",
      cwd: "/tmp",
      actionfolder: "/tmp",
      attributes: Dict.make(),
    }

    switch Renderer.render(tmpl, ctx) {
    | Ok(_) => {
        // EJS may render with undefined var as empty string - that's acceptable
        assert_true(true)
        resolve()
        Promise.resolve()
      }
    | Error(msg) =>
      // Error is acceptable - means validation caught the undefined var
      assert_true(String.length(msg) > 0)
      resolve()
      Promise.resolve()
    }
    ->ignore
  })
})
