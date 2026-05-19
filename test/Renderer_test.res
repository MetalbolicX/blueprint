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
})
