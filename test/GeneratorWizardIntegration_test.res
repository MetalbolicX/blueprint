open TestHelpers

type processHarness = {
  process: Ports.process,
  getExitCode: unit => option<int>,
}

let makeProcessHarness = (~cwd: string): processHarness => {
  let exitCode: ref<option<int>> = ref(None)
  let process: Ports.process = {
    cwd: () => cwd,
    env: () => Dict.make(),
    argv: () => ["node", "dist/main.mjs"],
    exit: code => {
      exitCode.contents = Some(code)
      throw(Not_found)
    },
    onSignal: (_, _) => (),
    removeSignalListeners: () => (),
  }
  {process, getExitCode: () => exitCode.contents}
}

let makeInteractiveIO = (~answers: array<string>, ~confirmAnswers: array<bool>): Ports.interactiveIO => {
  let answerIdx = ref(0)
  let confirmIdx = ref(0)

  {
    ask: _question => {
      let out = switch answers[answerIdx.contents] {
      | Some(v) => v
      | None => ""
      }
      answerIdx.contents = answerIdx.contents + 1
      Promise.resolve(out)
    },
    askConfirm: (~question as _, ~defaultYes=false) => {
      let out = switch confirmAnswers[confirmIdx.contents] {
      | Some(v) => v
      | None => defaultYes
      }
      confirmIdx.contents = confirmIdx.contents + 1
      Promise.resolve(out)
    },
    close: () => (),
  }
}

let makeDeps = (~cwd: string, ~answers: array<string>, ~confirmAnswers: array<bool>) => {
  let harness = makeProcessHarness(~cwd)
  let deps: Ports.deps = {
    fs: NodeJsFileSystem.make(),
    path: NodeJsPath.make(),
    process: harness.process,
    shell: NodeJsShell.make(),
    interactiveIO: makeInteractiveIO(~answers, ~confirmAnswers),
    argParser: NodeJsArgParser.make(),
  }
  (deps, harness)
}

suite("Generator wizard integration", () => {
  testAsync("runAddPrompt appends prompt to generator manifest", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let generatorDir = NodeJs.Path.join(tmpDir, "_templates/mygen")
    let manifestPath = NodeJs.Path.join(generatorDir, "manifest.yaml")

    let initialManifest =
      "# manifest comment\nname: mygen\nclassification: mygen\nprompts:\n  - name: existing\n    type: input\n    description: Existing\n"

    let (deps, harness) = makeDeps(
      ~cwd=tmpDir,
      ~answers=["componentName", "Component name", "input", "Button", ""],
      ~confirmAnswers=[false],
    )

    NodeJs.Fs.mkdir(generatorDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, initialManifest))
    ->Promise.then(_ => CommandsGenerator.runAddPrompt(~deps, ~name=Some("mygen")))
    ->Promise.then(_ => NodeJs.Fs.readFile(manifestPath, ~options={encoding: "utf8"}))
    ->Promise.then(updated => {
      switch harness.getExitCode() {
      | Some(_) => assert_false(true)
      | None => assert_true(true)
      }
      assert_true(String.includes(updated, "# manifest comment"))
      switch Manifest.parse(updated) {
      | Ok(manifest) =>
        switch manifest.prompts {
        | Some(prompts) => {
            assert_eq(Array.length(prompts), 2)
            switch prompts[1] {
            | Some(p) => {
                assert_eq(p.name, "componentName")
                assert_eq(p.description, "Component name")
              }
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runAddPrompt exits when generator is missing", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (deps, harness) = makeDeps(
      ~cwd=tmpDir,
      ~answers=["name", "Name", "input", "", ""],
      ~confirmAnswers=[],
    )

    CommandsGenerator.runAddPrompt(~deps, ~name=Some("missing"))
    ->Promise.then(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      assert_eq(harness.getExitCode(), Some(1))
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->ignore
  })

  testAsync("runAddFile writes template with full directive set", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let generatorDir = NodeJs.Path.join(tmpDir, "_templates/mygen")
    let manifestPath = NodeJs.Path.join(generatorDir, "manifest.yaml")
    let expectedTemplatePath = NodeJs.Path.join(generatorDir, "new/route.ejs.t")

    let manifest = "name: mygen\nclassification: mygen\nprompts: []\n"

    let (deps, harness) = makeDeps(
      ~cwd=tmpDir,
      ~answers=[
        "new",
        "route.ejs.t",
        "src/routes/<%= name %>.ts",
        "from,inject,after,before,atLine,skipIf,prepend,append,eofLast,force,unlessExists,tool,fetch,script",
        "./partials/route.ejs",
        "router.use",
        "import",
        "export default",
        "42",
        "__ROUTE__",
        "format",
        "https://example.com/file.txt",
        "setup",
        "export const route = true",
      ],
      ~confirmAnswers=[true, true, true, true, true],
    )

    NodeJs.Fs.mkdir(generatorDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, manifest))
    ->Promise.then(_ => CommandsGenerator.runAddFile(~deps, ~name=Some("mygen")))
    ->Promise.then(_ => NodeJs.Fs.readFile(expectedTemplatePath, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      switch harness.getExitCode() {
      | Some(_) => assert_false(true)
      | None => assert_true(true)
      }
      assert_true(String.includes(content, "to: src/routes/<%= name %>.ts"))
      assert_true(String.includes(content, "from: ./partials/route.ejs"))
      assert_true(String.includes(content, "inject: router.use"))
      assert_true(String.includes(content, "after: import"))
      assert_true(String.includes(content, "before: export default"))
      assert_true(String.includes(content, "at_line: 42"))
      assert_true(String.includes(content, "skip_if: __ROUTE__"))
      assert_true(String.includes(content, "prepend: true"))
      assert_true(String.includes(content, "append: true"))
      assert_true(String.includes(content, "eof_last: true"))
      assert_true(String.includes(content, "force: true"))
      assert_true(String.includes(content, "unless_exists: true"))
      assert_true(String.includes(content, "tool: format"))
      assert_true(String.includes(content, "fetch: https://example.com/file.txt"))
      assert_true(String.includes(content, "script: setup"))
      assert_true(String.includes(content, "export const route = true"))

      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runAddFile supports minimal flow with defaults", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let generatorDir = NodeJs.Path.join(tmpDir, "_templates/mygen")
    let manifestPath = NodeJs.Path.join(generatorDir, "manifest.yaml")
    let expectedTemplatePath = NodeJs.Path.join(generatorDir, "new/minimal.ejs.t")

    let manifest = "name: mygen\nclassification: mygen\nprompts: []\n"

    let (deps, harness) = makeDeps(
      ~cwd=tmpDir,
      ~answers=["", "minimal", "src/minimal.ts", "", "export const minimal = true"],
      ~confirmAnswers=[],
    )

    NodeJs.Fs.mkdir(generatorDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, manifest))
    ->Promise.then(_ => CommandsGenerator.runAddFile(~deps, ~name=Some("mygen")))
    ->Promise.then(_ => NodeJs.Fs.readFile(expectedTemplatePath, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      switch harness.getExitCode() {
      | Some(_) => assert_false(true)
      | None => assert_true(true)
      }
      assert_true(String.includes(content, "to: src/minimal.ts"))
      assert_true(String.includes(content, "export const minimal = true"))
      assert_false(String.includes(content, "append: true"))

      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("runList reads generator without exiting", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let generatorDir = NodeJs.Path.join(tmpDir, "_templates/mygen")
    let actionDir = NodeJs.Path.join(generatorDir, "new")
    let manifestPath = NodeJs.Path.join(generatorDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "item.ejs.t")

    let manifest = "name: mygen\nclassification: mygen\nprompts:\n  - name: item\n    type: input\n    description: Item\n"
    let templateContent = "---\nto: src/item.ts\n---\nexport const item = true\n"

    let (deps, harness) = makeDeps(~cwd=tmpDir, ~answers=[], ~confirmAnswers=[])

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, manifest))
    ->Promise.then(_ => NodeJs.Fs.writeFile(templatePath, templateContent))
    ->Promise.then(_ => CommandsGenerator.runList(~deps, ~name=Some("mygen")))
    ->Promise.then(_ => {
      switch harness.getExitCode() {
      | Some(_) => assert_false(true)
      | None => assert_true(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
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
