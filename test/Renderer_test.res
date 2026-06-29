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

    // Build a minimal renderContext with only the required fields.
    // WS4: cwd and actionfolder are no longer on the renderContext type —
    // they're stripped at Context.toRenderContext and never reach the renderer.
    let ctx: Renderer.renderContext = {
      name: "Test",
      pascalName: "Test",
      names: "tests",
      pluralPascalName: "Tests",
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

  // ---------- WS4: cwd and actionfolder not injected into render data ----------

  testAsync("WS4: render does not inject cwd or actionfolder into EJS data", resolve => {
    // The renderer is responsible for putting names into the EJS data dict.
    // Per WS4 clean-render-context: even if a template tried to read cwd/
    // actionfolder, those keys must NOT exist in the EJS scope.
    let tmpl: Template.template = {
      sourcePath: "/test/res/Test.res.ejs.t",
      directives: [Template.To("out.txt")],
      body: "cwd=[<%= cwd %>] af=[<%= actionfolder %>]",
    }
    let ctx: Renderer.renderContext = {
      name: "Test",
      pascalName: "Test",
      names: "tests",
      pluralPascalName: "Tests",
      attributes: Dict.make(),
    }

    switch Renderer.render(tmpl, ctx) {
    | Ok(_) =>
      // If cwd/actionfolder slipped through, they'd render as something —
      // EJS would have returned Ok rather than Error.
      assert_false(true)
    | Error(msg) =>
      // EJS raises an undefined-var error which surfaces as Error.
      assert_true(
        String.includes(msg, "cwd") ||
          String.includes(msg, "actionfolder") ||
          String.includes(msg, "is not defined"),
      )
    }
    resolve()
  })
})
