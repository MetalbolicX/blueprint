// Phase1_test — staging and rendering tests

open TestHelpers

suite("Phase1", () => {
  test("phase1Result: structure", () => {
    let result = {
      Phase1.stagingDir: "/tmp/blueprint-abc123",
      renderedFiles: [("/src/Hello.tsx.ejs.t", "src/Hello.tsx")],
      shellCommands: [],
    }

    assert_eq(result.stagingDir, "/tmp/blueprint-abc123")
    assert_eq(Array.length(result.renderedFiles), 1)
  })

  test("phase1Error: structure", () => {
    let err = {
      Phase1.stagingDir: "/tmp/blueprint-abc123",
      message: "Failed to render",
    }

    assert_eq(err.stagingDir, "/tmp/blueprint-abc123")
    assert_eq(err.message, "Failed to render")
  })

  test("resolveTargetPath: resolves to directive", () => {
    let _nv = Context.makeNameVariants("Hello")
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Hello",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.To("src/<%= Name %>.tsx"), ctx)
    switch result {
    | Some(path) => assert_eq(path, "src/Hello.tsx")
    | None => assert_false(true)
    }
  })

  test("resolveTargetPath: non-To directive returns None", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.Sh("npm install"), ctx)
    switch result {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })

  test("resolveTargetPath: EJS path renders correctly", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(Template.To("src/<%= name %>.tsx"), ctx)
    switch result {
    | Some(path) => assert_eq(path, "src/button.tsx")
    | None => assert_false(true)
    }
  })

  testAsync("run: resolves ScriptFile path relative to template directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let expectedScriptPath = NodeJs.Path.join(templateDir, "scripts/post.sh")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Sh("./scripts/post.sh"),
      ],
      body: "export default '<%= Name %>'",
    }

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.shellCommands), 1)
          switch phase1.shellCommands[0] {
          | Some(shellCommand) =>
            switch shellCommand.target {
            | Template.ScriptFile(path) => assert_eq(path, expectedScriptPath)
            | Template.InlineCommand(_) => assert_false(true)
            }
          | None => assert_false(true)
          }
          Phase2.rollback(phase1.stagingDir)->ignore
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
