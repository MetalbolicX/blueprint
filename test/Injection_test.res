// Injection_test — injection mode tests

open TestHelpers

suite("Injection", () => {
  test("injectRegex: basic replacement", () => {
    let result = Injection.injectRegex(
      "const old = require('module')",
      "const old",
      "const newValue",
    )

    switch result {
    | Ok(content) => assert_true(Js.String.includes(content, "const newValue"))
    | Error(_) => assert_false(true)
    }
  })

  test("injectRegex: invalid regex", () => {
    let result = Injection.injectRegex("content", "[invalid", "replacement")

    switch result {
    | Ok(_) => assert_false(true)
    | Error(_) => assert_true(true)
    }
  })

  test("insertAfter: inserts after match", () => {
    let result = Injection.insertAfter("const x = 1;\n// END", "// END", "\nconst y = 2;")

    switch result {
    | Ok(content) => assert_true(Js.String.includes(content, "const y = 2"))
    | Error(_) => assert_false(true)
    }
  })

  test("insertBefore: inserts before match", () => {
    let result = Injection.insertBefore(
      "// START\nconst x = 1;",
      "// START",
      "import foo from 'bar';\n",
    )

    switch result {
    | Ok(content) => assert_true(Js.String.includes(content, "import foo"))
    | Error(_) => assert_false(true)
    }
  })

  test("prependToContent: adds to start", () => {
    let result = Injection.prependToContent("existing", "prepended")
    assert_eq(result, "prepended\n\nexisting")
  })

  test("appendToContent: adds to end", () => {
    let result = Injection.appendToContent("existing", "appended")
    assert_eq(result, "existing\n\nappended")
  })

  test("apply: Inject directive", () => {
    let result = Injection.apply(
      ~existingContent="const old = 1;",
      ~renderedContent="const newVal = 2;",
      ~directive=Template.Inject("const old"),
    )

    switch result {
    | Ok(r) => {
        assert_true(r.applied)
        assert_true(Js.String.includes(r.content, "const newVal"))
      }
    | Error(_) => assert_false(true)
    }
  })

  test("apply: Prepend directive", () => {
    let result = Injection.apply(
      ~existingContent="body content",
      ~renderedContent="prepended content",
      ~directive=Template.Prepend,
    )

    switch result {
    | Ok(r) => {
        assert_true(r.applied)
        assert_true(Js.String.startsWith(r.content, "prepended content"))
      }
    | Error(_) => assert_false(true)
    }
  })

  test("apply: non-injection directive", () => {
    let result = Injection.apply(
      ~existingContent="content",
      ~renderedContent="ignored",
      ~directive=Template.Sh("echo test"),
    )

    switch result {
    | Ok(r) => {
        assert_false(r.applied)
        assert_eq(r.content, "content")
      }
    | Error(_) => assert_false(true)
    }
  })
})
