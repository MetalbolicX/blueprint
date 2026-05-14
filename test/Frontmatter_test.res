// Frontmatter_test — YAML frontmatter parsing tests

suite("Frontmatter", () => {
  test("parse: valid frontmatter with to directive", () => {
    let content = "---\nto: src/{{ .Name }}.go\n---\npackage main\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => {
        assert_eq(Js.Array.length(parsed.directives), 1)
        switch parsed.directives[0] {
        | Template.To(path) => assert_eq(path, "src/{{ .Name }}.go")
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
    | Ok(parsed) => {
        assert_eq(Js.Array.length(parsed.directives), 3)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: inject directive", () => {
    let content = "---\ninject: true\n---\nexport class Foo {}\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => {
        switch parsed.directives[0] {
        | Template.Inject(pattern) => assert_eq(pattern, "true")
        | _ => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: sh directive", () => {
    let content = "---\nsh: npm run format\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => {
        switch parsed.directives[0] {
        | Template.Sh(cmd) => assert_eq(cmd, "npm run format")
        | _ => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: prepend and append directives", () => {
    let content = "---\nprepend: true\nappend: true\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => {
        assert_eq(Js.Array.length(parsed.directives), 2)
      }
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
    | Ok(parsed) => {
        assert_eq(parsed.body, "")
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: unknown directive skipped", () => {
    let content = "---\nto: file.txt\nunknown: value\n---\ncontent\n"
    let result = Frontmatter.parse(content)
    switch result {
    | Ok(parsed) => {
        assert_eq(Js.Array.length(parsed.directives), 1)
      }
    | Error(_) => assert_false(true)
    }
  })
})