// TemplateRenderer_test — unit tests for TemplateRenderer error propagation

open TestHelpers

suite("TemplateRenderer.resolveTargetPath — error propagation", () => {
  let ejs = NodeJsEjs.make()

  test("EJS error in to: path surfaces (not 'No 'to' directive found')", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )
    // Template expression references an undefined EJS variable — EJS throws.
    let result = TemplateRenderer.resolveTargetPath(~ejs, Template.To("src/<%= undefined_var %>.tsx"), ctx)
    switch result {
    | Error(msg) =>
      // EJS error message format is unstable across versions; downgrade to
      // asserting the error does NOT contain the misleading "No 'to' directive found".
      assert_false(String.includes(msg, "No 'to' directive found"))
    | Ok(_) => assert_false(true) // should error
    }
  })

  test("valid to: path resolves successfully", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )
    let result = TemplateRenderer.resolveTargetPath(~ejs, Template.To("src/<%= Name %>.tsx"), ctx)
    switch result {
    | Ok(path) => assert_eq(path, "src/Hello.tsx")
    | Error(_) => assert_false(true) // should not error
    }
  })
})

suite("TemplateRenderer provenance gate", () => {
  let withCapturedWarnings: (array<string> => promise<unit>) => promise<unit> = %raw(`run => {
    const warnings = []
    const originalWarn = console.warn
    console.warn = (...args) => warnings.push(args.join(" "))
    return Promise.resolve(run(warnings)).finally(() => { console.warn = originalWarn })
  }`)

  let renderBody = (~sourcePath, ~body) => {
    let ctx = Context.build(~cwd="/workspace", ~actionfolder="/workspace/_templates", ~name="Hello", ())
    TemplateRenderer.render(
      ~template={sourcePath, directives: [Template.To("out.txt")], body},
      ~context=ctx,
      ~outputDir="/workspace/out",
      ~conflictDecisions=None,
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~ejs=NodeJsEjs.make(),
      ~process=NodeJsProcess.make(),
    )
  }

  testAsync("marked template with control-flow EJS renders with advisory", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let templatePath = NodeJs.Path.join(dir, "action.ejs.t")
    NodeJs.Fs.writeFile(NodeJs.Path.join(dir, ".blueprint-provenance"), "source: test\n")
    ->Promise.then(_ =>
      withCapturedWarnings(warnings =>
        renderBody(~sourcePath=templatePath, ~body="<% if (name) { %>hello<% } %>")->Promise.then(result => {
          switch result {
          | Ok(Some(output)) => assert_eq(output.renderedBody, "hello")
          | _ => assert_false(true)
          }
          assert_true(warnings->Array.some(warning =>
            String.includes(warning, "Advisory: registry template") && String.includes(warning, templatePath)
          ))
          resolve()
          Promise.resolve()
        })
      )
    )
    ->ignore
  })

  testAsync("unmarked template with control-flow EJS renders unchanged", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let result = renderBody(~sourcePath=NodeJs.Path.join(dir, "action.ejs.t"), ~body="<% if (name) { %>hello<% } %>")
    result->Promise.then(value => {
      switch value {
      | Ok(Some(output)) => assert_eq(output.renderedBody, "hello")
      | _ => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("marked template with interpolation renders without warning", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let templatePath = NodeJs.Path.join(dir, "action.ejs.t")
    NodeJs.Fs.writeFile(NodeJs.Path.join(dir, ".blueprint-provenance"), "source: test\n")
    ->Promise.then(_ =>
      withCapturedWarnings(warnings =>
        renderBody(~sourcePath=templatePath, ~body="hello <%= name %>")->Promise.then(result => {
          switch result {
          | Ok(Some(output)) => assert_eq(output.renderedBody, "hello hello")
          | _ => assert_false(true)
          }
          assert_eq(Array.length(warnings), 0)
          resolve()
          Promise.resolve()
        })
      )
    )
    ->ignore
  })
})
