// Phase0_test — prompt resolution tests

open TestHelpers

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

  testAsync("detectConflicts: returns empty when no templates have To directive", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.Prepend],
        body: "content",
      },
    ]

    Phase0.detectConflicts(~templates, ~outputDir=tmpDir, ~force=false)
    ->Promise.then(conflicts => {
      assert_eq(Array.length(conflicts), 0)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("detectConflicts: returns empty when no target file exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "tmpl.ejs.t"),
        directives: [Template.To("Hello.tsx")],
        body: "content",
      },
    ]

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ =>
      Phase0.detectConflicts(~templates, ~outputDir=outDir, ~force=false)
    )
    ->Promise.then(conflicts => {
      assert_eq(Array.length(conflicts), 0)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("detectConflicts: returns conflict when target file already exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
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
      Phase0.detectConflicts(~templates, ~outputDir=outDir, ~force=false)
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

  testAsync("detectConflicts: force=true still returns conflicts (resolver handles overwrite)", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")
    let targetFile = NodeJs.Path.join(outDir, "Hello.tsx")
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
      Phase0.detectConflicts(~templates, ~outputDir=outDir, ~force=true)
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
})
