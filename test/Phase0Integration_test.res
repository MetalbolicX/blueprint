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
