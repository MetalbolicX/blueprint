// Phase1_test — staging and rendering tests

open TestHelpers
open Commit

suite("Phase1", () => {
  let ejs = NodeJsEjs.make()

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

    let result = Phase1.resolveTargetPath(~ejs, Template.To("src/<%= Name %>.tsx"), ctx)
    switch result {
    | Ok(path) => assert_eq(path, "src/Hello.tsx")
    | Error(_) => assert_false(true)
    }
  })

  test("resolveTargetPath: non-To directive returns Error", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(~ejs, Template.Tool("npm install"), ctx)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "No 'to' directive"))
    }
  })

  test("resolveTargetPath: EJS path renders correctly", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates",
      ~name="Button",
      (),
    )

    let result = Phase1.resolveTargetPath(~ejs, Template.To("src/<%= name %>.tsx"), ctx)
    switch result {
    | Ok(path) => assert_eq(path, "src/button.tsx")
    | Error(_) => assert_false(true)
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
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~process=processAdapter,
        ~ejs=ejs,
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
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.shellCommands), 2)
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
                let expected = NodeJs.Path.resolve(NodeJs.Process.cwd(), "_templates/component/scripts/setup.sh")
                assert_eq(path, expected)
              }
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.renderedFiles), 1)
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.renderedFiles), 1)
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.renderedFiles), 0)
          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
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

  // --- Deterministic ordering tests (deterministic-pipeline-ordering change) ---

  // Test 3.1: renderedFiles must match input template order regardless of which
  // parallel render branch's I/O finishes first.
  testAsync("run: order-preserved-under-racing-io", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDirA = NodeJs.Path.join(tmpDir, "_templates/component/a")
    let templateDirB = NodeJs.Path.join(tmpDir, "_templates/component/b")
    let templateDirC = NodeJs.Path.join(tmpDir, "_templates/component/c")
    let sourceA = NodeJs.Path.join(templateDirA, "Alpha.tsx.ejs.t")
    let sourceB = NodeJs.Path.join(templateDirB, "Beta.tsx.ejs.t")
    let sourceC = NodeJs.Path.join(templateDirC, "Gamma.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDirA, ~name="X", ())

    // Deliberately varied body sizes so completion order across the parallel
    // branches is unlikely to equal source order. The post-collection pass must
    // restore source order regardless.
    let largeBody = String.repeat("x", 50_000)
    let smallBody = "tiny"

    let templateA: Template.template = {
      sourcePath: sourceA,
      directives: [Template.To("src/Alpha.tsx")],
      body: largeBody ++ " A=<%= Name %>",
    }
    let templateB: Template.template = {
      sourcePath: sourceB,
      directives: [Template.To("src/Beta.tsx")],
      body: smallBody,
    }
    let templateC: Template.template = {
      sourcePath: sourceC,
      directives: [Template.To("src/Gamma.tsx")],
      body: largeBody ++ largeBody ++ " C=<%= Name %>",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDirA, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(templateDirB, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.mkdir(templateDirC, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[templateA, templateB, templateC],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          assert_eq(Array.length(phase1.renderedFiles), 3)

          // Assert exact source→target mapping in input order.
          switch phase1.renderedFiles[0] {
          | Some((src, tgt)) => {
              assert_eq(src, sourceA)
              assert_eq(tgt, "src/Alpha.tsx")
            }
          | None => assert_false(true)
          }
          switch phase1.renderedFiles[1] {
          | Some((src, tgt)) => {
              assert_eq(src, sourceB)
              assert_eq(tgt, "src/Beta.tsx")
            }
          | None => assert_false(true)
          }
          switch phase1.renderedFiles[2] {
          | Some((src, tgt)) => {
              assert_eq(src, sourceC)
              assert_eq(tgt, "src/Gamma.tsx")
            }
          | None => assert_false(true)
          }

          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
        }
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // Test 3.2: shellCommands must group by template position and preserve
  // directive declaration order inside each template.
  testAsync("run: shell-commands-follow-template-and-directive-order", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDirA = NodeJs.Path.join(tmpDir, "_templates/component/a")
    let templateDirB = NodeJs.Path.join(tmpDir, "_templates/component/b")
    let sourceA = NodeJs.Path.join(templateDirA, "First.tsx.ejs.t")
    let sourceB = NodeJs.Path.join(templateDirB, "Second.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDirA, ~name="X", ())

    // Fetch directives need no shellConfig and emit one shellCommand each.
    // Order within each template: url-a, url-b, url-c.
    // Order across templates: all of templateA first, then all of templateB.
    let templateA: Template.template = {
      sourcePath: sourceA,
      directives: [
        Template.To("src/First.tsx"),
        Template.Fetch("https://example.com/a-first.ejs"),
        Template.Fetch("https://example.com/a-second.ejs"),
        Template.Fetch("https://example.com/a-third.ejs"),
      ],
      body: "first body",
    }
    let templateB: Template.template = {
      sourcePath: sourceB,
      directives: [
        Template.To("src/Second.tsx"),
        Template.Fetch("https://example.com/b-first.ejs"),
        Template.Fetch("https://example.com/b-second.ejs"),
      ],
      body: "second body",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    NodeJs.Fs.mkdir(templateDirA, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(templateDirB, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[templateA, templateB],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok(phase1) => {
          // 3 from templateA + 2 from templateB = 5 total.
          assert_eq(Array.length(phase1.shellCommands), 5)

          // templateA commands first, in directive order.
          switch phase1.shellCommands[0] {
          | Some(c) =>
            switch c.target {
            | Template.Fetch(url) => assert_eq(url, "https://example.com/a-first.ejs")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          switch phase1.shellCommands[1] {
          | Some(c) =>
            switch c.target {
            | Template.Fetch(url) => assert_eq(url, "https://example.com/a-second.ejs")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          switch phase1.shellCommands[2] {
          | Some(c) =>
            switch c.target {
            | Template.Fetch(url) => assert_eq(url, "https://example.com/a-third.ejs")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }

          // templateB commands second, in directive order.
          switch phase1.shellCommands[3] {
          | Some(c) =>
            switch c.target {
            | Template.Fetch(url) => assert_eq(url, "https://example.com/b-first.ejs")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }
          switch phase1.shellCommands[4] {
          | Some(c) =>
            switch c.target {
            | Template.Fetch(url) => assert_eq(url, "https://example.com/b-second.ejs")
            | _ => assert_false(true)
            }
          | None => assert_false(true)
          }

          rollback(phase1.stagingDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~fs, ~pathSecurity=NodeJsPathSecurity.make())->ignore
        }
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // Test 3.3: when one template fails, the run must surface an error AND
  // remove the staging directory.
  testAsync("run: error-aborts-and-cleans-staging", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templateDirA = NodeJs.Path.join(tmpDir, "_templates/component/a")
    let templateDirB = NodeJs.Path.join(tmpDir, "_templates/component/b")
    let sourceA = NodeJs.Path.join(templateDirA, "Good.tsx.ejs.t")
    let sourceB = NodeJs.Path.join(templateDirB, "Bad.tsx.ejs.t")
    let outputDir = NodeJs.Path.join(tmpDir, "out")

    let context = Context.build(~cwd=tmpDir, ~actionfolder=templateDirA, ~name="X", ())

    // templateA: succeeds.
    let templateA: Template.template = {
      sourcePath: sourceA,
      directives: [Template.To("src/Good.tsx")],
      body: "good body",
    }
    // templateB: legacy `sh:` directive in frontmatter is rejected upstream
    // (already covered by existing tests) — using it here guarantees an Error.
    let templateB: Template.template = {
      sourcePath: sourceB,
      directives: [],
      body: "---\nsh: npm run lint\n---\nexport const x = 1\n",
    }

    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()

    // Run the pipeline; we assert the error shape and capture the stagingDir.
    NodeJs.Fs.mkdir(templateDirA, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(templateDirB, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase1.run(
        ~templates=[templateA, templateB],
        ~context,
        ~outputDir,
        ~conflictDecisions=None,
        ~shellConfig=None,
        ~fs,
        ~path=pathAdapter,
        ~process=processAdapter,
        ~ejs=ejs,
      ~pathSecurity=NodeJsPathSecurity.make(),
      )
    )
    ->Promise.then(result =>
      switch result {
      | Error(err) => {
          // Error message is non-empty and references the failing source path.
          assert_true(String.length(err.message) > 0)
          assert_true(String.includes(err.message, sourceB))
          Promise.resolve(err.stagingDir)
        }
      | Ok(_) => {
          assert_false(true)
          Promise.resolve("")
        }
      }
    )
    ->Promise.then(stagingDir => {
      // Probe whether the staging dir still exists. After cleanup it MUST be gone.
      NodeJs.Fs.fileExists(stagingDir)
    })
    ->Promise.then(stillExists => {
      assert_eq(stillExists, false)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
