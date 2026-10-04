// Discovery_test — discovery and generator lookup tests

open TestHelpers

let makeCountingFs = (readPaths: ref<array<string>>): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()
  {
    readFile: (file, ~options=?) => {
      readPaths := readPaths.contents->Array.concat([file])
      base.readFile(file, ~options?)
    },
    writeFile: (file, content, ~options=?) => base.writeFile(file, content, ~options?),
    mkdir: (dir, ~options=?) => base.mkdir(dir, ~options?),
    rm: (target, ~options=?) => base.rm(target, ~options?),
    cp: (fromPath, toPath, ~options=?) => base.cp(fromPath, toPath, ~options?),
    readdir: (dir, ~options=?) => base.readdir(dir, ~options?),
    fileExists: file => base.fileExists(file),
    stat: file => base.stat(file),
    lstat: file => base.lstat(file),
    realpath: file => base.realpath(file),
    makeStagingDir: prefix => base.makeStagingDir(prefix),
  }
}

let rejectFsError: string => promise<'a> = %raw(`message => Promise.reject(Object.assign(new Error(message), {code: message.split(":")[0]}))`)

let makeObservedFs = (~peak: ref<int>, ~inFlight: ref<int>, ~failRead: option<(string, string)>, ~failReaddir: option<(string, string)>): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()
  {
    ...base,
    readFile: async (file, ~options=?) => {
      switch failRead {
      | Some((failedPath, message)) if file == failedPath => await rejectFsError(message)
      | _ =>
        inFlight := inFlight.contents + 1
        if inFlight.contents > peak.contents { peak := inFlight.contents }
        try {
          let content = await base.readFile(file, ~options?)
          inFlight := inFlight.contents - 1
          content
        } catch {
        | exn =>
          inFlight := inFlight.contents - 1
          throw(exn)
        }
      }
    },
    readdir: (dir, ~options=?) => switch failReaddir {
    | Some((failedPath, message)) if dir == failedPath => rejectFsError(message)
    | _ => base.readdir(dir, ~options?)
    },
  }
}

let captureWarnings: (unit => promise<'a>) => promise<(array<string>, 'a)> = %raw(`async run => {
  const warnings = [];
  const original = console.warn;
  console.warn = (...args) => warnings.push(args.join(" "));
  try { return [warnings, await run()]; }
  finally { console.warn = original; }
}`)

let captureMetaWarnings: (unit => promise<array<Discovery.generatorMeta>>) => promise<
  (array<string>, array<Discovery.generatorMeta>),
> = %raw(`async run => {
  const warnings = [];
  const original = console.warn;
  console.warn = (...args) => warnings.push(args.join(" "));
  try { return [warnings, await run()]; }
  finally { console.warn = original; }
}`)

let makeTemplateFixture = (~count: int): promise<(string, string)> => {
  let tmpDir = NodeJs.Os.makeStagingDir()
  let genDir = NodeJs.Path.join(tmpDir, "component")
  NodeJs.Fs.mkdir(genDir, ~options={recursive: true})
  ->Promise.then(_ => NodeJs.Fs.writeFile(
    NodeJs.Path.join(genDir, "manifest.yaml"),
    "name: test\nclassification: component\nprompts: []\n",
  ))
  ->Promise.then(_ => {
    let rec setupActions = i => {
      if i >= count {
        Promise.resolve()
      } else {
        let actionDir = NodeJs.Path.join(genDir, "action" ++ Int.toString(i))
        NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
        ->Promise.then(_ => NodeJs.Fs.writeFile(
          NodeJs.Path.join(actionDir, "file.txt.ejs.t"),
          "---\nto: file.txt\n---\nbody",
        ))
        ->Promise.then(_ => setupActions(i + 1))
      }
    }
    setupActions(0)
  })
  ->Promise.then(_ => Promise.resolve((tmpDir, genDir)))
}

suite("Discovery", () => {
  let fs = NodeJsFileSystem.make()
  let pathAdapter = NodeJsPath.make()
  let yamlParser = NodeJsYamlParser.make()
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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
    let _ = Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, "/non/existent/path")
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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

  testAsync("template EACCES warns and skips only the unreadable template", resolve => {
    let _ = makeTemplateFixture(~count=2)->Promise.then(fixture => {
      let (tmpDir, genDir) = fixture
      let failed = NodeJs.Path.join(genDir, "action0/file.txt.ejs.t")
      let peak = ref(0)
      let inFlight = ref(0)
      let faultFs = makeObservedFs(~peak, ~inFlight, ~failRead=Some((failed, "EACCES: permission denied")), ~failReaddir=None)
      captureWarnings(() => Discovery.discoverIn(~fs=faultFs, ~path=pathAdapter, ~yamlParser, tmpDir))
      ->Promise.then(((warnings, gens)) => {
        assert_eq(Array.length(gens), 1)
        let gen = gens[0]->Option.getOr({Discovery.name: "", path: "", templates: []})
        assert_eq(Array.length(gen.templates), 1)
        assert_true(warnings->Array.some(w => String.includes(w, failed)))
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => { resolve(); Promise.resolve() })
      })
    })
  })

  testAsync("template ENOENT remains a silent skip", resolve => {
    let _ = makeTemplateFixture(~count=2)->Promise.then(fixture => {
      let (tmpDir, genDir) = fixture
      let failed = NodeJs.Path.join(genDir, "action0/file.txt.ejs.t")
      let peak = ref(0)
      let inFlight = ref(0)
      let faultFs = makeObservedFs(~peak, ~inFlight, ~failRead=Some((failed, "ENOENT: no such file or directory")), ~failReaddir=None)
      captureWarnings(() => Discovery.discoverIn(~fs=faultFs, ~path=pathAdapter, ~yamlParser, tmpDir))
      ->Promise.then(((warnings, gens)) => {
        assert_eq(Array.length(warnings), 0)
        switch gens[0] {
        | Some(gen) => assert_eq(Array.length(gen.templates), 1)
        | None => assert_false(true)
        }
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => { resolve(); Promise.resolve() })
      })
    })
  })

  testAsync("action directory EACCES warns and keeps other actions", resolve => {
    let _ = makeTemplateFixture(~count=2)->Promise.then(fixture => {
      let (tmpDir, genDir) = fixture
      let failed = NodeJs.Path.join(genDir, "action0")
      let peak = ref(0)
      let inFlight = ref(0)
      let faultFs = makeObservedFs(~peak, ~inFlight, ~failRead=None, ~failReaddir=Some((failed, "EACCES: permission denied")))
      captureWarnings(() => Discovery.discoverIn(~fs=faultFs, ~path=pathAdapter, ~yamlParser, tmpDir))
      ->Promise.then(((warnings, gens)) => {
        assert_true(warnings->Array.some(w => String.includes(w, failed)))
        switch gens[0] {
        | Some(gen) => assert_eq(Array.length(gen.templates), 1)
        | None => assert_false(true)
        }
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => { resolve(); Promise.resolve() })
      })
    })
  })

  testAsync("discoverGenerators warns when a search path is unreadable", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let peak = ref(0)
    let inFlight = ref(0)
    let faultFs = makeObservedFs(
      ~peak,
      ~inFlight,
      ~failRead=None,
      ~failReaddir=Some((tmpDir, "EACCES: permission denied")),
    )
    let captured = captureMetaWarnings(() =>
      Discovery.discoverGenerators(~fs=faultFs, ~path=pathAdapter, ~yamlParser, ~searchPaths=[tmpDir], ()),
    )
    let _ = captured->Promise.then(((warnings, metaResults)) => {
      assert_eq(Array.length(metaResults), 0)
      assert_true(warnings->Array.some(w => String.includes(w, tmpDir) && String.includes(w, "EACCES")))
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => { resolve(); Promise.resolve() })
    })
  })

  testAsync("template reads are bounded to eight in flight", resolve => {
    let _ = makeTemplateFixture(~count=20)->Promise.then(fixture => {
      let (tmpDir, _genDir) = fixture
      let peak = ref(0)
      let inFlight = ref(0)
      let observedFs = makeObservedFs(~peak, ~inFlight, ~failRead=None, ~failReaddir=None)
      Discovery.discoverIn(~fs=observedFs, ~path=pathAdapter, ~yamlParser, tmpDir)
      ->Promise.then(_ => {
        assert_true(peak.contents <= 8)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => { resolve(); Promise.resolve() })
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
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

  // --- hook-path discovery and load-guard tests ---

  testAsync("discover: create-res-project generator carries both hook paths", resolve => {
    let examplesPath = NodeJs.Path.resolve(NodeJs.Process.cwd(), "examples")
    let _ = Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, examplesPath)
    ->Promise.then(gens => {
      switch Discovery.findByClassification(gens, "create-res-project") {
      | Some(gen) =>
        switch gen.manifest {
        | Some(m) =>
          switch m.hooks {
          | Some(h) => {
              assert_eq(h.preGenerate, Some("scripts/read-package-name.mjs"))
              assert_eq(h.postGenerate, Some("scripts/setup-rescript.mjs"))
              resolve()
            }
          | None => {
              assert_false(true)
              resolve()
            }
          }
        | None => {
            assert_false(true)
            resolve()
          }
        }
      | None => {
          assert_false(true)
          resolve()
        }
      }
      Promise.resolve()
    })
    ->Promise.catch(exn => {
      throw(exn)
    })
  })

  testAsync("discover: manifest with nonexistent hook file returns error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let genDir = NodeJs.Path.join(tmpDir, "testgen")
    let newDir = NodeJs.Path.join(genDir, "new")

    let _ = NodeJs.Fs.mkdir(genDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(newDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(genDir, "manifest.yaml"),
        "name: test\nclassification: test\nhooks:\n  pre_generate: scripts/nonexistent.mjs\n",
      )
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(newDir, "index.txt.ejs.t"),
        "---\nto: out.txt\n---\nhello\n",
      )
    )
    ->Promise.then(_ => Discovery.discoverIn(~fs, ~path=pathAdapter, ~yamlParser, tmpDir))
    ->Promise.then(gens => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->Promise.then(_ => {
        // Generator with missing hook script must be excluded
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

  testAsync("discoverGenerators loads template bodies only for selected generator", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let readPaths = ref([])
    let countingFs = makeCountingFs(readPaths)
    let generators = ["A", "B", "C"]
    let setup = generators->Array.map(generator => {
      let genDir = NodeJs.Path.join(tmpDir, generator)
      let actionDir = NodeJs.Path.join(genDir, "new")
      NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
      ->Promise.then(_ => NodeJs.Fs.writeFile(
        NodeJs.Path.join(genDir, "manifest.yaml"),
        "name: " ++ generator ++ "\nclassification: " ++ generator ++ "\nprompts: []\n",
      ))
      ->Promise.then(_ => NodeJs.Fs.writeFile(
        NodeJs.Path.join(actionDir, "one.txt.ejs.t"), "---\nto: one.txt\n---\none",
      ))
      ->Promise.then(_ => NodeJs.Fs.writeFile(
        NodeJs.Path.join(actionDir, "two.txt.ejs.t"), "---\nto: two.txt\n---\ntwo",
      ))
    })

    let _ = Promise.all(setup)->Promise.then(_ =>
      Discovery.discoverGenerators(
        ~fs=countingFs,
        ~path=pathAdapter,
        ~yamlParser,
        ~searchPaths=[tmpDir],
        (),
      )
    )->Promise.then(metas => {
      let selected = Discovery.findByClassificationMeta(metas, "B")
      switch selected {
      | None => {
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Some(meta) => {
          assert_eq(meta.path, NodeJs.Path.join(tmpDir, "B"))
          Discovery.loadGeneratorTemplates(~fs=countingFs, ~path=pathAdapter, meta.path)
          ->Promise.then(templates => {
            assert_eq(Array.length(templates), 2)
            let bodyReads = readPaths.contents->Array.filter(p => String.endsWith(p, ".ejs.t"))
            assert_eq(Array.length(bodyReads), 2)
            assert_true(bodyReads->Array.every(p => String.startsWith(p, meta.path)))
            let manifestReads = readPaths.contents->Array.filter(p => String.endsWith(p, "manifest.yaml"))
            assert_true(Array.length(manifestReads) <= 3)
            resolve()
            Promise.resolve()
          })
        }
      }
    })->Promise.catch(exn => { throw(exn) })
  })

  testAsync("discoverGenerators skips invalid manifests before template reads", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let readPaths = ref([])
    let countingFs = makeCountingFs(readPaths)
    let entries = [("good", "prompts: []"), ("bad", "prompts: [unterminated"), ("other", "prompts: []")]
    let setup = entries->Array.map(((name, manifestBody)) => {
      let genDir = NodeJs.Path.join(tmpDir, name)
      let actionDir = NodeJs.Path.join(genDir, "new")
      NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
      ->Promise.then(_ => NodeJs.Fs.writeFile(
        NodeJs.Path.join(genDir, "manifest.yaml"),
        "name: " ++ name ++ "\nclassification: " ++ name ++ "\n" ++ manifestBody ++ "\n",
      ))
      ->Promise.then(_ => NodeJs.Fs.writeFile(
        NodeJs.Path.join(actionDir, "file.txt.ejs.t"), "---\nto: file.txt\n---\nbody",
      ))
    })

    let _ = Promise.all(setup)->Promise.then(_ =>
      Discovery.discoverGenerators(
        ~fs=countingFs,
        ~path=pathAdapter,
        ~yamlParser,
        ~searchPaths=[tmpDir],
        (),
      )
    )->Promise.then(metas => {
      assert_eq(Array.length(metas), 2)
      switch Discovery.findByClassificationMeta(metas, "good") {
      | None => {
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Some(meta) => {
          Discovery.loadGeneratorTemplates(~fs=countingFs, ~path=pathAdapter, meta.path)
          ->Promise.then(templates => {
            assert_eq(Array.length(templates), 1)
            let badTemplatePath = NodeJs.Path.join(tmpDir, "bad/new/file.txt.ejs.t")
            assert_false(readPaths.contents->Array.includes(badTemplatePath))
            resolve()
            Promise.resolve()
          })
        }
      }
    })->Promise.catch(exn => { throw(exn) })
  })

  test("findByClassificationMeta preserves search path precedence", () => {
    let first: Discovery.generatorMeta = {
      name: "same",
      path: "/first/_templates/same",
      manifest: None,
    }
    let later: Discovery.generatorMeta = {
      name: "same",
      path: "/later/templates/same",
      manifest: None,
    }
    switch Discovery.findByClassificationMeta([first, later], "same") {
    | Some(meta) => assert_eq(meta.path, first.path)
    | None => assert_false(true)
    }
  })
})
