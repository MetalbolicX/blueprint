// Template_test — directive parsing tests

open TestHelpers

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

  test("directive: From variant", () => {
    let dir = Template.From("./partials/component.ejs")
    switch dir {
    | Template.From(path) => assert_eq(path, "./partials/component.ejs")
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

  test("directive: AtLine variant", () => {
    let dir = Template.AtLine(3)
    switch dir {
    | Template.AtLine(line) => assert_eq(line, 3)
    | _ => assert_false(true)
    }
  })

  test("directive: SkipIf variant", () => {
    let dir = Template.SkipIf("already-added")
    switch dir {
    | Template.SkipIf(pattern) => assert_eq(pattern, "already-added")
    | _ => assert_false(true)
    }
  })

  test("directive: EofLast variant", () => {
    let dir = Template.EofLast
    switch dir {
    | Template.EofLast => assert_true(true)
    | _ => assert_false(true)
    }
  })

  test("directive: UnlessExists variant", () => {
    let dir = Template.UnlessExists
    switch dir {
    | Template.UnlessExists => assert_true(true)
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
      Template.sourcePath: "/templates/Hello.tsx.ejs.t",
      directives: [Template.To("src/Hello.tsx")],
      body: "export const Hello = () => <div/>\n",
    }

    assert_eq(tmpl.sourcePath, "/templates/Hello.tsx.ejs.t")
    assert_eq(Array.length(tmpl.directives), 1)
    assert_eq(String.includes(tmpl.body, "export"), true)
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
      Template.target: Template.InlineCommand("npm run format"),
      sourcePath: "/templates/Hello.tsx.ejs.t",
    }

    switch sc.target {
    | Template.InlineCommand(cmd) => assert_eq(cmd, "npm run format")
    | _ => assert_false(true)
    }
    assert_eq(sc.sourcePath, "/templates/Hello.tsx.ejs.t")
  })

  test("shellTarget: ScriptFile variant", () => {
    let target = Template.ScriptFile("/templates/scripts/post.sh")
    switch target {
    | Template.ScriptFile(path) => assert_eq(path, "/templates/scripts/post.sh")
    | _ => assert_false(true)
    }
  })

  test("directive: Tool variant", () => {
    let dir = Template.Tool("format")
    switch dir {
    | Template.Tool(name) => assert_eq(name, "format")
    | _ => assert_false(true)
    }
  })

  test("directive: Fetch variant", () => {
    let dir = Template.Fetch("https://raw.githubusercontent.com/.../gitignore")
    switch dir {
    | Template.Fetch(url) => assert_eq(url, "https://raw.githubusercontent.com/.../gitignore")
    | _ => assert_false(true)
    }
  })

  test("shellTarget: ToolCall variant", () => {
    let target = Template.ToolCall({
      name: "format",
      toolDef: {
        name: "format",
        command: "npx prettier --write",
      },
      sourcePath: "/templates/Hello.tsx.ejs.t",
    })
    switch target {
    | Template.ToolCall(tc) =>
      assert_eq(tc.name, "format")
      assert_eq(tc.toolDef.command, "npx prettier --write")
      assert_eq(tc.sourcePath, "/templates/Hello.tsx.ejs.t")
    | _ => assert_false(true)
    }
  })

  test("shellCommand: with ToolCall target", () => {
    let sc = {
      Template.target: Template.ToolCall({
        name: "lint",
        toolDef: {
          name: "lint",
          command: "npx eslint",
          args: ["--fix", "."],
        },
        sourcePath: "/templates/Hello.tsx.ejs.t",
      }),
      sourcePath: "/templates/Hello.tsx.ejs.t",
    }

    switch sc.target {
    | Template.ToolCall(tc) =>
      assert_eq(tc.name, "lint")
      assert_eq(tc.sourcePath, "/templates/Hello.tsx.ejs.t")
    | _ => assert_false(true)
    }
  })
})
