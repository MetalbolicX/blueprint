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

    let result = Phase1.resolveTargetPath(Template.Tool("npm install"), ctx)
    switch result {
    | Some(_) => assert_false(true)
    | None => assert_eq(result, None)
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

  testAsync("run: missing tool fails before shell queue is created", resolve => {
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
      | Error(err) => assert_true(String.includes(err.message, "Tool not found"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: missing script fails before shell queue is created", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.Script("setup"),
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
        ~shellConfig=Some({enabled: true}),
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(err) => assert_true(String.includes(err.message, "Script not found"))
      | Ok(_) => assert_false(true)
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

    let shellCfg: Config.shellConfig = {
      enabled: true,
      tools: [{name: "prettier", command: "prettier"}],
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

  testAsync("run: From directive rejects path traversal outside template tree", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outsidePath = NodeJs.Path.join(tmpDir, "outside.ejs")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.From("../../../../outside.ejs"),
      ],
      body: "fallback",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outsidePath, "should-not-be-readable"))
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
      | Error(err) => assert_true(String.includes(err.message, "Invalid 'from' path outside template tree"))
      | Ok(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: From directive accepts safe relative file inside template tree", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let partialPath = NodeJs.Path.join(templateDir, "partials/content.ejs")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [
        Template.To("src/<%= Name %>.tsx"),
        Template.From("./partials/content.ejs"),
      ],
      body: "fallback",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(partialPath), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(partialPath, "safe external <%= Name %>"))
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

  // --- Invalid directive handling ---

  testAsync("run: template with invalid directive in frontmatter body produces Error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")
    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    // Legacy sh frontmatter should now fail upstream
    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [],
      body: "---\nsh: npm run lint\n---\nexport default '<%= Name %>'\n",
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
      | Error(err) => {
          assert_true(String.length(err.message) > 0)
          assert_true(String.includes(err.message, templateSourcePath))
        }
      | Ok(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: mixed valid and invalid directives - error wins", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")
    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [],
      body: "---\nsh: npm run lint\nto: src/<%= name %>.tsx\n---\nexport default '<%= Name %>'\n",
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
      | Error(err) => {
          assert_true(String.length(err.message) > 0)
          assert_true(String.includes(err.message, templateSourcePath))
        }
      | Ok(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: unknown directive key produces Error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDir = NodeJs.Path.join(tmpDir, "_templates/component/new")
    let templateSourcePath = NodeJs.Path.join(templateDir, "index.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")
    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDir, ~name="Button", ())

    let template: Template.template = {
      sourcePath: templateSourcePath,
      directives: [],
      body: "---\nunknown_directive: somevalue\nto: src/<%= name %>.tsx\n---\nexport default '<%= Name %>'\n",
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
      | Error(err) => {
          assert_true(String.length(err.message) > 0)
          assert_true(String.includes(err.message, templateSourcePath))
        }
      | Ok(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
