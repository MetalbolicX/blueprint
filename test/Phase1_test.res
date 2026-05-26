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

  // NOTE: ScriptFile behavior removed in shell-security PR
  // Sh directives are now handled differently based on shell.enabled
  // Tool directives create ToolCall shellTargets
  // Fetch directives create Fetch shellTargets

  testAsync("run: collects Fetch directive as Fetch shellTarget", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Fetch("https://example.com/template.json"),
      ],
      body: "export default '<%= Name %>'",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
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
            | Template.Fetch(url) => assert_eq(url, "https://example.com/template.json")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: collects Tool directive as ToolCall when tool exists in config", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Tool("eslint"),
      ],
      body: "export default '<%= Name %>'",
    }

    let shellCfg: Config.shellConfig = {
      enabled: true,
      tools: [{name: "eslint", command: "eslint"}],
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=Some(shellCfg),
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
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
            | Template.ToolCall({name}) => assert_eq(name, "eslint")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: produces InlineCommand when tool not found", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Tool("eslint"),
      ],
      body: "export default '<%= Name %>'",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
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
            | Template.InlineCommand(cmd) => assert_eq(cmd, "tool-not-found: eslint")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: collects multiple directive types as separate shellTargets", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Fetch("https://example.com/data.json"),
        Template.Tool("prettier"),
      ],
      body: "export default '<%= Name %>'",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.shellCommands), 2)
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: Script directive resolves relative actionfolder to absolute script path", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDirAbs = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDirAbs, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(
      ~cwd=tmpDir,
      ~actionfolder="_templates/component",
      ~name="Button",
      (),
    )

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Script("setup"),
      ],
      body: "export default '<%= Name %>'",
    }

    let shellCfg: Config.shellConfig = {
      enabled: true,
      scripts: [{name: "setup", path: "scripts/setup.sh"}],
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDirAbs, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=Some(shellCfg),
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
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
            | Template.ScriptFile(path) => {
                let expected = NodeJs.Path.resolve(NodeJs.NodeProcess.cwd(), "_templates/component/scripts/setup.sh")
                assert_eq(path, expected)
              }
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: From directive uses external file body", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let partialPath = NodeJs.Path.join(templateDir, "partial.ejs")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.From("partial.ejs"),
      ],
      body: "fallback",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(partialPath, "external <%= Name %>"))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.renderedFiles), 1)
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: UnlessExists skips template when target exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")
    let targetPath = NodeJs.Path.join(outputDir, "src/Button.tsx")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.UnlessExists,
      ],
      body: "export default '<%= Name %>'",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(targetPath), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(templateDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetPath, "existing"))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[template],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.renderedFiles), 0)
          Phase2.rollback(phase1.stagingDir, ~fs)->ignore
        }
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
