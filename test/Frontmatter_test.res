// Frontmatter_test — YAML frontmatter parsing tests

open TestHelpers

let pathPort = NodeJsPath.make()

suite("Frontmatter", () => {
  test("parse: valid frontmatter with to directive", () => {
    let content = "---\nto: src/{{ .Name }}.go\n---\npackage main\n"
    let result = Frontmatter.parse(~path=pathPort, content)
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
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) => assert_eq(Array.length(parsed.directives), 3)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: inject directive", () => {
    let content = "---\ninject: true\n---\nexport class Foo {}\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) => switch parsed.directives[0] {
      | Some(Template.Inject(pattern)) => assert_eq(pattern, "true")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: sh directive is rejected", () => {
    let content = "---\nsh: npm run format\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: prepend and append directives", () => {
    let content = "---\nprepend: true\nappend: true\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) => assert_eq(Array.length(parsed.directives), 2)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: missing frontmatter", () => {
    let content = "no frontmatter\npackage main\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: empty body", () => {
    let content = "---\nto: file.txt\n---\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) => assert_eq(parsed.body, "")
    | Error(_) => assert_false(true)
    }
  })

  test("parse: unknown directive is rejected", () => {
    let content = "---\nto: file.txt\nunknown: value\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: tool directive", () => {
    let content = "---\ntool: format\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Tool(name)) => assert_eq(name, "format")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: from directive", () => {
    let content = "---\nfrom: ./partials/header.ejs\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.From(path)) => assert_eq(path, "./partials/header.ejs")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: unless_exists directive", () => {
    let content = "---\nunless_exists: true\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.UnlessExists) => assert_true(true)
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: at_line directive", () => {
    let content = "---\nat_line: 3\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.AtLine(line)) => assert_eq(line, 3)
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: skip_if directive", () => {
    let content = "---\nskip_if: __INIT__\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.SkipIf(pattern)) => assert_eq(pattern, "__INIT__")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: eof_last directive", () => {
    let content = "---\neof_last: true\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.EofLast) => assert_true(true)
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: fetch directive", () => {
    let content = "---\nfetch: https://raw.githubusercontent.com/.../gitignore\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
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
    let result = Frontmatter.parse(~path=pathPort, content)
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
    let result = Frontmatter.parse(~path=pathPort, content)
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
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(_) => assert_true(true)
    }
  })

  // --- Step 4: directive value validation ---

  test("parse: rejects absolute path in to directive", () => {
    let content = "---\nto: /etc/abs\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: rejects parent-segment path in to directive", () => {
    let content = "---\nto: ../escape\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: rejects absolute path in from directive", () => {
    let content = "---\nfrom: /abs/path\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: rejects parent-segment path in from directive", () => {
    let content = "---\nfrom: ../other\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: accepts normal relative path in to directive", () => {
    let content = "---\nto: src/x.ts\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.To(path)) => assert_eq(path, "src/x.ts")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: accepts normal relative path in from directive", () => {
    let content = "---\nfrom: templates/x.ejs.t\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.From(path)) => assert_eq(path, "templates/x.ejs.t")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: rejects non-http scheme in fetch directive", () => {
    let content = "---\nfetch: file:///etc/passwd\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: rejects javascript scheme in fetch directive", () => {
    let content = "---\nfetch: javascript:alert(1)\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: accepts https URL in fetch directive", () => {
    let content = "---\nfetch: https://ok.example.com/file\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Fetch(url)) => assert_eq(url, "https://ok.example.com/file")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: accepts http URL in fetch directive", () => {
    let content = "---\nfetch: http://ok.example.com/file\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Fetch(url)) => assert_eq(url, "http://ok.example.com/file")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: accepts tool directive (lookup key is safe by design)", () => {
    let content = "---\ntool: somename\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Tool(name)) => assert_eq(name, "somename")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: accepts script directive (lookup key is safe by design)", () => {
    let content = "---\nscript: somename\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Ok(parsed) =>
      switch parsed.directives[0] {
      | Some(Template.Script(name)) => assert_eq(name, "somename")
      | _ => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: rejects to directive with mixed separators containing parent segment", () => {
    let content = "---\nto: foo\\..\\bar\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: rejects from directive with parent segment in middle", () => {
    let content = "---\nfrom: templates/../etc/passwd\n---\ncontent\n"
    let result = Frontmatter.parse(~path=pathPort, content)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })
})
