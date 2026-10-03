// Phase0_test — prompt resolution tests

open TestHelpers

// plan 043: all conflict tests exercise rendered target detection.
let detectRenderedConflicts = async (~templates, ~outputDir, ~force, ~fs, ~path) =>
  switch await Phase0.detectRenderedConflicts(
    ~templates,
    ~outputDir,
    ~force,
    ~ejs=TestPorts.stubEjs,
    ~attributes=Dict.make(),
    ~fs,
    ~path,
    ~pathSecurity=TestPorts.stubPathSecurity,
  ) {
  | Ok(conflicts) => conflicts
  | Error(_) => {
      assert_false(true)
      []
    }
  }

suite("Phase0", () => {
  test("phase0Result: structure", () => {
    let result = {
      Phase0.resolvedAttributes: Dict.make(),
      conflicts: [],
    }

    assert_true(Dict.toArray(result.resolvedAttributes)->Array.length == 0)
    assert_eq(Array.length(result.conflicts), 0)
  })

  test("conflictFile: structure", () => {
    let cf = {
      Phase0.sourcePath: "/templates/Hello.tsx.ejs.t",
      targetPath: "/output/Hello.tsx",
    }

    assert_eq(cf.sourcePath, "/templates/Hello.tsx.ejs.t")
    assert_eq(cf.targetPath, "/output/Hello.tsx")
  })

  testAsync("detectRenderedConflicts: returns empty when no templates have To directive", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.Prepend],
        body: "content",
      },
    ]

    detectRenderedConflicts(~templates, ~outputDir=tmpDir, ~force=false, ~fs, ~path=pathAdapter)
    ->Promise.then(conflicts => {
      assert_eq(Array.length(conflicts), 0)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("detectRenderedConflicts: returns empty when no target file exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.To("Hello.tsx")],
        body: "content",
      },
    ]

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ =>
      detectRenderedConflicts(~templates, ~outputDir=outDir, ~force=false, ~fs, ~path=pathAdapter)
    )
    ->Promise.then(conflicts => {
      assert_eq(Array.length(conflicts), 0)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("detectRenderedConflicts: returns conflict when target file already exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.To("Hello.tsx")],
        body: "content",
      },
    ]

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "existing"))
    ->Promise.then(_ =>
      detectRenderedConflicts(~templates, ~outputDir=outDir, ~force=false, ~fs, ~path=pathAdapter)
    )
    ->Promise.then(conflicts => {
      assert_eq(Array.length(conflicts), 1)
      switch conflicts[0] {
      | Some(cf) => {
          assert_eq(cf.sourcePath, NodeJs.Path.join(tmpDir, "tmpl.ejs.t"))
          assert_eq(cf.targetPath, targetFile)
        }
      | None => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("detectRenderedConflicts: force=true still returns conflicts (resolver handles overwrite)", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.To("Hello.tsx")],
        body: "content",
      },
    ]

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "existing"))
    ->Promise.then(_ =>
      detectRenderedConflicts(~templates, ~outputDir=outDir, ~force=true, ~fs, ~path=pathAdapter)
    )
    ->Promise.then(conflicts => {
      // force=true does NOT suppress conflict detection; it tells the resolver to auto-overwrite
      assert_eq(Array.length(conflicts), 1)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("detectRenderedConflicts: unless_exists templates are excluded", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.To("Hello.tsx"), Template.UnlessExists],
        body: "content",
      },
    ]

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "existing"))
    ->Promise.then(_ =>
      detectRenderedConflicts(~templates, ~outputDir=outDir, ~force=false, ~fs, ~path=pathAdapter)
    )
    ->Promise.then(conflicts => {
      assert_eq(Array.length(conflicts), 0)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
