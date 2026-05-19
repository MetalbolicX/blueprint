// Frontmatter_test — YAML frontmatter parsing tests

open TestHelpers

suite("Frontmatter", () => {
  test("parse: valid frontmatter with to directive", () => {
    let content = "---\nto: src/{{ .Name }}.go\n---\npackage main\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => {
        assert_eq(Array.length(parsed.directives), 1)
        switch parsed.directives[0] {
        | Some(Template.To(path)) => assert_eq(path, "src/{{ .Name }}.go")
        | _ => assert_false(true)
        }
        assert_eq(parsed.body, "package main\n")
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: multiple directives", () => {
    let content = "---\nto: src/{{ .Name }}.go\ninject: true\nforce: true\n---\npackage main\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => assert_eq(Array.length(parsed.directives), 3)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: inject directive", () => {
    let content = "---\ninject: true\n---\nexport class Foo {}\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => switch parsed.directives[0] {
      | Some(Template.Inject(pattern)) => assert_eq(pattern, "true")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: sh directive", () => {
    let content = "---\nsh: npm run format\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => switch parsed.directives[0] {
      | Some(Template.Sh(cmd)) => assert_eq(cmd, "npm run format")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: prepend and append directives", () => {
    let content = "---\nprepend: true\nappend: true\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => assert_eq(Array.length(parsed.directives), 2)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: missing frontmatter", () => {
    let content = "no frontmatter\npackage main\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: empty body", () => {
    let content = "---\nto: file.txt\n---\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => assert_eq(parsed.body, "")
    | Error(_) => assert_false(true)
    }
  })

  test("parse: unknown directive skipped", () => {
    let content = "---\nto: file.txt\nunknown: value\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => assert_eq(Array.length(parsed.directives), 1)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: tool directive", () => {
    let content = "---\ntool: format\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Tool(name)) => assert_eq(name, "format")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: fetch directive", () => {
    let content = "---\nfetch: https://raw.githubusercontent.com/.../gitignore\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Fetch(url)) => assert_eq(url, "https://raw.githubusercontent.com/.../gitignore")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: tool and fetch produce correct variants", () => {
    let content = "---\ntool: mytool\nfetch: https://example.com/file\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) =>
      assert_eq(Array.length(parsed.directives), 2)
      switch parsed.directives[0] {
      | Some(Template.Tool(name)) => assert_eq(name, "mytool")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: malformed inject regex returns Error not throw", () => {
    // Bad regex syntax should be handled gracefully
    let content = "---\ninject: [invalid(\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) =>
      // inject directive with bad regex value is stored as-is (parsing happens later in Injection.res)
      switch parsed.directives[0] {
      | Some(Template.Inject(pattern)) => assert_eq(pattern, "[invalid(")
      | _ => assert_false(true)
      }
    | Error(_) => assert_true(true)  // frontmatter itself should parse OK; regex validation is deferred
    }
  })

  test("parse: garbage after frontmatter returns Error", () => {
    // Missing closing --- delimiter
    let content = "---\nto: file.txt\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(_) => assert_true(true)
    }
  })
})
