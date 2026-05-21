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
    | Ok(content) => assert_true(String.includes(content, "const newValue"))
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
    | Ok(content) => assert_true(String.includes(content, "const y = 2"))
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
    | Ok(content) => assert_true(String.includes(content, "import foo"))
    | Error(_) => assert_false(true)
    }
  })

  test("insertAtLine: inserts content at line", () => {
    let result = Injection.insertAtLine("a\nb\nc", 2, "x")

    switch result {
    | Ok(content) => assert_eq(content, "a\nx\nb\nc")
    | Error(_) => assert_false(true)
    }
  })

  test("insertAtLine: line out of range", () => {
    let result = Injection.insertAtLine("a\nb", 10, "x")

    switch result {
    | Ok(_) => assert_false(true)
    | Error(_) => assert_true(true)
    }
  })

  test("shouldSkip: true when regex matches", () => {
    let result = Injection.shouldSkip("const a = 1", "a =")
    switch result {
    | Ok(v) => assert_true(v)
    | Error(_) => assert_false(true)
    }
  })

  test("shouldSkip: false when regex does not match", () => {
    let result = Injection.shouldSkip("const a = 1", "b =")
    switch result {
    | Ok(v) => assert_false(v)
    | Error(_) => assert_false(true)
    }
  })

  test("trimTrailingNewline: removes final newline", () => {
    let result = Injection.trimTrailingNewline("hello\n")
    assert_eq(result, "hello")
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
        assert_true(String.includes(r.content, "const newVal"))
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
        assert_true(String.startsWith(r.content, "prepended content"))
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

  test("apply: AtLine directive", () => {
    let result = Injection.apply(
      ~existingContent="line1\nline2",
      ~renderedContent="inserted",
      ~directive=Template.AtLine(2),
    )

    switch result {
    | Ok(r) => {
        assert_true(r.applied)
        assert_eq(r.content, "line1\ninserted\nline2")
      }
    | Error(_) => assert_false(true)
    }
  })

  test("apply: SkipIf blocks injection", () => {
    let result = Injection.apply(
      ~existingContent="// marker",
      ~renderedContent="new content",
      ~directive=Template.Append,
      ~allDirectives=[Template.SkipIf("marker")],
    )

    switch result {
    | Ok(r) => {
        assert_false(r.applied)
        assert_eq(r.content, "// marker")
      }
    | Error(_) => assert_false(true)
    }
  })

  test("apply: EofLast trims rendered content", () => {
    let result = Injection.apply(
      ~existingContent="head",
      ~renderedContent="tail\n",
      ~directive=Template.Append,
      ~allDirectives=[Template.EofLast],
    )

    switch result {
    | Ok(r) => {
        assert_true(r.applied)
        assert_eq(r.content, "head\n\ntail")
      }
    | Error(_) => assert_false(true)
    }
  })
})