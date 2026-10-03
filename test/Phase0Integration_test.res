// Phase0Integration_test — phase0 prompt resolution and conflict detection integration tests

open TestHelpers

let makeInteractiveIO = (~answers: array<string>=[]): Ports.interactiveIO => {
  let answerIdx = ref(0)
  {
    ask: _question => {
      let out = switch answers[answerIdx.contents] {
      | Some(v) => v
      | None => ""
      }
      answerIdx.contents = answerIdx.contents + 1
      Promise.resolve(out)
    },
    askConfirm: (~question as _, ~defaultYes=false) => Promise.resolve(defaultYes),
    close: () => (),
  }
}

let runConflictGeneration = (~tmpDir, ~templates, ~answer, ~force, ~askCount) => {
  let outDir = NodeJs.Path.join(tmpDir, "out")
  let askCalls = ref(0)
  let io: Ports.interactiveIO = {
    ask: _ => {
      askCalls.contents = askCalls.contents + 1
      Promise.resolve(answer)
    },
    askConfirm: (~question as _, ~defaultYes=false) => Promise.resolve(defaultYes),
    close: () => (),
  }
  let deps: Ports.deps = {
    fs: NodeJsFileSystem.make(),
    path: NodeJsPath.make(),
    process: NodeJsProcess.make(),
    shell: NodeJsShell.make(),
    interactiveIO: io,
    argParser: NodeJsArgParser.make(),
    yamlParser: TestPorts.stubYamlParser,
    ejs: TestPorts.stubEjs,
    fetcher: NodeJsFetcher.make(),
    pathSecurity: NodeJsPathSecurity.make(),
    shellBuilder: NodeJsShellBuilder.make(),
    envFilter: NodeJsEnvFilter.make(),
    hooks: NodeJsHooks.make(),
  }
  let gen: Discovery.generator = {name: "conflict-test", path: tmpDir, templates}
  Engine.run(
    ~generator=gen,
    ~name="Hello",
    ~cliAttributes=Dict.make(),
    ~outputDir=outDir,
    ~force,
    ~deps,
  )->Promise.then(result => {
    assert_eq(askCalls.contents, askCount)
    Promise.resolve(result)
  })
}

suite("Phase0 Integration", () => {
  testAsync("run: resolves input prompts from manifest into resolvedAttributes", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()

    let io = makeInteractiveIO(~answers=["Button", "A button component"])

    let prompts: array<Manifest.prompt> = [
      {name: "componentName", promptType: Manifest.Input, description: "Component name"},
      {name: "description", promptType: Manifest.Input, description: "Description"},
    ]

    let gen: Discovery.generator = {
      name: "test-gen",
      path: tmpDir,
      templates: [],
      manifest: {
        name: "test-gen",
        classification: "test",
        prompts: prompts,
      },
    }

    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())

    Phase0.run(~io, ~ejs=TestPorts.stubEjs, ~generator=gen, ~context, ~outputDir=tmpDir, ~force=false, ~fs, ~path=pathAdapter)
    ->Promise.then(result => {
      switch result {
      | Ok(phase0Result) => {
          switch Dict.get(phase0Result.resolvedAttributes, "componentName") {
          | Some(v) => assert_eq(v, "Button")
          | None => assert_false(true)
          }
          switch Dict.get(phase0Result.resolvedAttributes, "description") {
          | Some(v) => assert_eq(v, "A button component")
          | None => assert_false(true)
          }
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns empty resolvedAttributes when manifest has no prompts", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()

    let io = makeInteractiveIO(~answers=[])

    let gen: Discovery.generator = {
      name: "test-gen",
      path: tmpDir,
      templates: [],
    }

    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())

    Phase0.run(~io, ~ejs=TestPorts.stubEjs, ~generator=gen, ~context, ~outputDir=tmpDir, ~force=false, ~fs, ~path=pathAdapter)
    ->Promise.then(result => {
      switch result {
      | Ok(phase0Result) => {
          let entries = Dict.toArray(phase0Result.resolvedAttributes)
          assert_eq(Array.length(entries), 0)
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: detects conflicts when target file already exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()

    let io = makeInteractiveIO(~answers=[])

    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
      directives: [Template.To("Hello.tsx")],
      body: "content",
    }

    let gen: Discovery.generator = {
      name: "test-gen",
      path: tmpDir,
      templates: [template],
    }

    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "existing"))
    ->Promise.then(_ =>
      Phase0.run(~io, ~ejs=TestPorts.stubEjs, ~generator=gen, ~context, ~outputDir=outDir, ~force=false, ~fs, ~path=pathAdapter)
    )
    ->Promise.then(result => {
      switch result {
      | Ok(phase0Result) => {
          assert_eq(Array.length(phase0Result.conflicts), 1)
          switch phase0Result.conflicts[0] {
          | Some(cf) => {
              assert_eq(cf.sourcePath, NodeJs.Path.join(tmpDir, "tmpl.ejs.t"))
              assert_eq(cf.targetPath, targetFile)
            }
          | None => assert_false(true)
          }
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: detects an existing templated target using prompt attributes", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "templated.ejs.t"),
      directives: [Template.To("<%= componentName %>.tsx")],
      body: "content",
    }
    let gen: Discovery.generator = {
      name: "test-gen",
      path: tmpDir,
      templates: [template],
      manifest: {
        name: "test-gen",
        classification: "test",
        prompts: [{name: "componentName", promptType: Manifest.Input, description: "Component name"}],
      },
    }
    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())
    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "existing"))
    ->Promise.then(_ =>
      Phase0.run(
        ~io=makeInteractiveIO(~answers=["Hello"]),
        ~ejs=TestPorts.stubEjs,
        ~generator=gen,
        ~context,
        ~outputDir=outDir,
        ~force=false,
        ~fs,
        ~path=pathAdapter,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(phase0Result) => {
          assert_eq(Array.length(phase0Result.conflicts), 1)
          assert_eq(phase0Result.conflicts[0]->Option.map(cf => cf.targetPath), Some(targetFile))
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: excludes UnlessExists templates from conflict detection", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()

    let io = makeInteractiveIO(~answers=[])

    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
      directives: [Template.To("Hello.tsx"), Template.UnlessExists],
      body: "content",
    }

    let gen: Discovery.generator = {
      name: "test-gen",
      path: tmpDir,
      templates: [template],
    }

    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "existing"))
    ->Promise.then(_ =>
      Phase0.run(~io, ~ejs=TestPorts.stubEjs, ~generator=gen, ~context, ~outputDir=outDir, ~force=false, ~fs, ~path=pathAdapter)
    )
    ->Promise.then(result => {
      switch result {
      | Ok(phase0Result) => assert_eq(Array.length(phase0Result.conflicts), 0)
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: rendered target errors name the source template and fail before writes", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let sourcePath = NodeJs.Path.join(tmpDir, "broken.ejs.t")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let template: Template.template = {
      sourcePath,
      directives: [Template.To("<%= missing.value %>.tsx")],
      body: "content",
    }
    let gen: Discovery.generator = {name: "test-gen", path: tmpDir, templates: [template]}
    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())
    Phase0.run(
      ~io=makeInteractiveIO(),
      ~ejs=TestPorts.stubEjs,
      ~generator=gen,
      ~context,
      ~outputDir=outDir,
      ~force=false,
      ~fs,
      ~path=pathAdapter,
    )->Promise.then(result => {
      switch result {
      | Error(message) => {
          assert_true(String.includes(message, sourcePath))
          assert_true(String.includes(message, "Failed to render 'to' path"))
        }
      | Ok(_) => assert_false(true)
      }
      NodeJs.Fs.access(outDir)->Promise.then(_ => {
        assert_false(true)
        Promise.resolve()
      })->Promise.catch(_ => {
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      })->ignore
      Promise.resolve()
    })->ignore
  })

  // plan 043
  testAsync("run: NoAll skips the rendered target without writing", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let target = NodeJs.Path.join(outDir, "hello.tsx")
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "new.ejs.t"),
      directives: [Template.To("<%= name %>.tsx")],
      body: "new content",
    }
    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(target, "existing"))
    ->Promise.then(_ => runConflictGeneration(~tmpDir, ~templates=[template], ~answer="no", ~force=false, ~askCount=1))
    ->Promise.then(_ => NodeJs.Fs.readFile(target, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      assert_eq(content, "existing")
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("run: yes overwrites the rendered target with transactional backup", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let target = NodeJs.Path.join(outDir, "hello.tsx")
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "new.ejs.t"),
      directives: [Template.To("<%= name %>.tsx")],
      body: "new content",
    }
    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(target, "existing"))
    ->Promise.then(_ => runConflictGeneration(~tmpDir, ~templates=[template], ~answer="yes", ~force=false, ~askCount=1))
    ->Promise.then(_ => NodeJs.Fs.readFile(target, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      assert_eq(content, "new content")
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("run: force overwrites rendered target without prompting", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let target = NodeJs.Path.join(outDir, "hello.tsx")
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "new.ejs.t"),
      directives: [Template.To("<%= name %>.tsx")],
      body: "forced content",
    }
    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(target, "existing"))
    ->Promise.then(_ => runConflictGeneration(~tmpDir, ~templates=[template], ~answer="", ~force=true, ~askCount=0))
    ->Promise.then(_ => NodeJs.Fs.readFile(target, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      assert_eq(content, "forced content")
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("run: duplicate rendered targets share the overwrite decision", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let target = NodeJs.Path.join(outDir, "hello.tsx")
    let templates: array<Template.template> = [
      {sourcePath: NodeJs.Path.join(tmpDir, "one.ejs.t"), directives: [Template.To("<%= name %>.tsx")], body: "one"},
      {sourcePath: NodeJs.Path.join(tmpDir, "two.ejs.t"), directives: [Template.To("<%= name %>.tsx")], body: "two"},
    ]
    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(target, "existing"))
    ->Promise.then(_ => runConflictGeneration(~tmpDir, ~templates, ~answer="no", ~force=false, ~askCount=1))
    ->Promise.then(_ => NodeJs.Fs.readFile(target, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      assert_eq(content, "existing")
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("run: force=true resolves prompts from defaults without interactive I/O", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()

    // Empty answers — force mode should use defaults, not touch IO
    let io = makeInteractiveIO(~answers=[])

    let prompts: array<Manifest.prompt> = [
      {name: "componentName", promptType: Manifest.Input, description: "Component name", default: "Button"},
      {name: "description", promptType: Manifest.Input, description: "Description", default: "A button"},
    ]

    let gen: Discovery.generator = {
      name: "test-gen",
      path: tmpDir,
      templates: [],
      manifest: {
        name: "test-gen",
        classification: "test",
        prompts: prompts,
      },
    }

    let context = Context.build(~cwd=tmpDir, ~actionfolder=tmpDir, ~name="Test", ())

    Phase0.run(~io, ~ejs=TestPorts.stubEjs, ~generator=gen, ~context, ~outputDir=tmpDir, ~force=true, ~fs, ~path=pathAdapter)
    ->Promise.then(result => {
      switch result {
      | Ok(phase0Result) => {
          switch Dict.get(phase0Result.resolvedAttributes, "componentName") {
          | Some(v) => assert_eq(v, "Button")
          | None => assert_false(true)
          }
          switch Dict.get(phase0Result.resolvedAttributes, "description") {
          | Some(v) => assert_eq(v, "A button")
          | None => assert_false(true)
          }
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
