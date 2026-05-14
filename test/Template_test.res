// Template_test — directive parsing tests

suite("Template", () => {
  test("directive: To variant", () => {
    let dir = Template.To("src/{{ .Name }}.go")
    switch dir {
    | Template.To(path) => assert_eq(path, "src/{{ .Name }}.go")
    | _ => assert_false(true)
    }
  })

  test("directive: Inject variant", () => {
    let dir = Template.Inject("const \\w+ = require")
    switch dir {
    | Template.Inject(pattern) => assert_eq(pattern, "const \\w+ = require")
    | _ => assert_false(true)
    }
  })

  test("directive: After variant", () => {
    let dir = Template.After("// INJECT HERE")
    switch dir {
    | Template.After(pattern) => assert_eq(pattern, "// INJECT HERE")
    | _ => assert_false(true)
    }
  })

  test("directive: Before variant", () => {
    let dir = Template.Before("// BEFORE")
    switch dir {
    | Template.Before(pattern) => assert_eq(pattern, "// BEFORE")
    | _ => assert_false(true)
    }
  })

  test("directive: Prepend variant", () => {
    let dir = Template.Prepend
    switch dir {
    | Template.Prepend => assert_true(true)
    | _ => assert_false(true)
    }
  })

  test("directive: Append variant", () => {
    let dir = Template.Append
    switch dir {
    | Template.Append => assert_true(true)
    | _ => assert_false(true)
    }
  })

  test("directive: Force variant", () => {
    let dir = Template.Force
    switch dir {
    | Template.Force => assert_true(true)
    | _ => assert_false(true)
    }
  })

  test("directive: Sh variant", () => {
    let dir = Template.Sh("npm run format")
    switch dir {
    | Template.Sh(cmd) => assert_eq(cmd, "npm run format")
    | _ => assert_false(true)
    }
  })

  test("template: full structure", () => {
    let tmpl = {
      sourcePath: "/templates/Hello.tsx.ejs.t",
      directives: [Template.To("src/Hello.tsx")],
      body: "export const Hello = () => <div/>\n",
    }

    assert_eq(tmpl.sourcePath, "/templates/Hello.tsx.ejs.t")
    assert_eq(Js.Array.length(tmpl.directives), 1)
    assert_eq(Js.String.includes(tmpl.body, "export"), true)
  })

  test("renderedFile: structure", () => {
    let rf = {
      Template.sourcePath: "/templates/Hello.tsx.ejs.t",
      targetPath: "src/Hello.tsx",
      content: "export const Hello = () => <div/>\n",
      isInjection: false,
    }

    assert_eq(rf.targetPath, "src/Hello.tsx")
    assert_eq(rf.isInjection, false)
  })

  test("shellCommand: structure", () => {
    let sc = {
      Template.command: "npm run format",
      sourcePath: "/templates/Hello.tsx.ejs.t",
    }

    assert_eq(sc.command, "npm run format")
    assert_eq(sc.sourcePath, "/templates/Hello.tsx.ejs.t")
  })
})