// Discovery_test — discovery and generator lookup tests

open TestHelpers

suite("Discovery", () => {
  let fs = NodeJsFileSystem.make()
  let pathAdapter = NodeJsPath.make()
  test("findByClassification: returns generator when exists", () => {
    let gens = [
      {
        Discovery.name: "component",
        path: "/workspace/_templates/component",
        templates: [],
      },
      {
        Discovery.name: "page",
        path: "/workspace/_templates/page",
        templates: [],
      },
    ]

    switch Discovery.findByClassification(gens, "component") {
    | Some(g) => assert_eq(g.name, "component")
    | None => assert_false(true)
    }
  })

  test("findByClassification: returns None when missing", () => {
    let gens = [
      {
        Discovery.name: "component",
        path: "/workspace/_templates/component",
        templates: [],
      },
    ]

    assert_eq(Discovery.findByClassification(gens, "missing"), None)
  })

  testAsync("discoverIn: returns generators from real directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let componentDir = NodeJs.Path.join(tmpDir, "component")
    let newDir = NodeJs.Path.join(componentDir, "new")

    let _ = NodeJs.Fs.mkdir(componentDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(newDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(componentDir, "manifest.yaml"),
        "name: test\nclassification: component\nprompts: []\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "index.tsx.ejs.t"),
        "---\nto: src/{{ .name }}.tsx\n---\nimport React from 'react'\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        assert_true(Array.length(gens) >= 1)
        switch gens[0] {
        | Some(g) => assert_eq(g.name, "component")
        | None => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })

  testAsync("discoverIn: returns empty array for non-existent directory", resolve => {
    let _ = Discovery.discoverIn(~fs, ~path=pathAdapter, "/non/existent/path")
    ->Promise.then(gens => {
      assert_eq(Array.length(gens), 0)
      resolve()
      Promise.resolve()
    })
  })

  testAsync("discoverIn: skips files in base directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()

    let _ = NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(tmpDir, "not_a_directory.txt"),
        "not a generator",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        assert_eq(Array.length(gens), 0)
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })

  testAsync("discoverIn: skips malformed templates and keeps valid ones", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let componentDir = NodeJs.Path.join(tmpDir, "component")
    let newDir = NodeJs.Path.join(componentDir, "new")

    let _ = NodeJs.Fs.mkdir(componentDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(newDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(componentDir, "manifest.yaml"),
        "name: test\nclassification: component\nprompts: []\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "index.tsx.ejs.t"),
        "---\nto: src/{{ .name }}.tsx\n---\nimport React from 'react'\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "broken.tsx.ejs.t"),
        "---\nto src/{{ .name }}.tsx\n---\nimport React from 'react'\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        assert_eq(Array.length(gens), 1)
        switch gens[0] {
        | Some(g) => {
            assert_eq(g.name, "component")
            assert_eq(Array.length(g.templates), 1)
          }
        | None => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })

  testAsync("discoverIn: returns structured outcome when every template is malformed", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let componentDir = NodeJs.Path.join(tmpDir, "component")
    let newDir = NodeJs.Path.join(componentDir, "new")

    let _ = NodeJs.Fs.mkdir(componentDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(newDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "broken.tsx.ejs.t"),
        "---\nto src/{{ .name }}.tsx\n---\nimport React from 'react'\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        assert_eq(Array.length(gens), 1)
        switch gens[0] {
        | Some(g) => assert_eq(Array.length(g.templates), 0)
        | None => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })

  // --- Fail-fast contract tests ---

  testAsync("discoverIn: excludes generator whose manifest has select prompt without options", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let componentDir = NodeJs.Path.join(tmpDir, "component")
    let newDir = NodeJs.Path.join(componentDir, "new")

    let _ = NodeJs.Fs.mkdir(componentDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(newDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(componentDir, "manifest.yaml"),
        "name: bad\nclassification: bad\nprompts:\n  - name: type\n    type: select\n    description: Pick\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "index.tsx.ejs.t"),
        "---\nto: src/{{ .name }}.tsx\n---\nimport React from 'react'\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        // Generator with invalid manifest must be excluded entirely
        assert_eq(Array.length(gens), 0)
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })

  testAsync("discoverIn: excludes generator whose manifest is malformed YAML", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let componentDir = NodeJs.Path.join(tmpDir, "component")
    let newDir = NodeJs.Path.join(componentDir, "new")

    let _ = NodeJs.Fs.mkdir(componentDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(newDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(componentDir, "manifest.yaml"),
        "name: bad\nclassification: bad\nprompts: [unterminated",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "index.tsx.ejs.t"),
        "---\nto: src/{{ .name }}.tsx\n---\nimport React from 'react'\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        // Malformed manifest → generator excluded, no crash
        assert_eq(Array.length(gens), 0)
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })

  testAsync("discoverIn: valid manifest passes alongside invalid manifest", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()

    // valid generator
    let validDir = NodeJs.Path.join(tmpDir, "valid")
    let validNewDir = NodeJs.Path.join(validDir, "new")
    // invalid generator
    let invalidDir = NodeJs.Path.join(tmpDir, "invalid")
    let invalidNewDir = NodeJs.Path.join(invalidDir, "new")

    let _ = NodeJs.Fs.mkdir(validNewDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(invalidNewDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(validDir, "manifest.yaml"),
        "name: ok\nclassification: ok\nprompts: []\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(invalidDir, "manifest.yaml"),
        "name: bad\nclassification: bad\nprompts:\n  - name: t\n    type: select\n    description: x\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(validNewDir, "x.tsx.ejs.t"),
        "---\nto: src/x.tsx\n---\nhello\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(invalidNewDir, "x.tsx.ejs.t"),
        "---\nto: src/x.tsx\n---\nhello\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        // Only the valid generator should remain
        assert_eq(Array.length(gens), 1)
        switch gens[0] {
        | Some(g) => assert_eq(g.name, "valid")
        | None => assert_false(true)
        }
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(exn => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        throw(exn)
      })
    })
  })
})
