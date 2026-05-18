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

  test("isFileReference: detects dot-slash path", () => {
    assert_true(Frontmatter.isFileReference("./scripts/post.sh"))
  })

  test("isFileReference: detects parent-relative path", () => {
    assert_true(Frontmatter.isFileReference("../shared/validate.py"))
  })

  test("isFileReference: detects extension-only filename", () => {
    assert_true(Frontmatter.isFileReference("script.py"))
  })

  test("isFileReference: treats inline npm command as non-file", () => {
    assert_false(Frontmatter.isFileReference("npm run format"))
  })

  test("isFileReference: treats multi-word echo command as non-file", () => {
    assert_false(Frontmatter.isFileReference("echo hello world"))
  })

  test("isFileReference: detects extension with relative dir", () => {
    assert_true(Frontmatter.isFileReference("scripts/setup.go"))
  })

  test("isFileReference: no extension single token is non-file", () => {
    assert_false(Frontmatter.isFileReference("make"))
  })
})
