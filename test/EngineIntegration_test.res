// EngineIntegration_test — full pipeline integration tests with real file creation

open TestHelpers

let deps: Ports.deps = {
  fs: NodeJsFileSystem.make(),
  path: NodeJsPath.make(),
  process: NodeJsProcess.make(),
  shell: NodeJsShell.make(),
  interactiveIO: NodeJsInteractiveIO.make(()),
  argParser: NodeJsArgParser.make(),
  yamlParser: NodeJsYamlParser.make(),
  ejs: NodeJsEjs.make(),
  fetcher: NodeJsFetcher.make(),
  pathSecurity: NodeJsPathSecurity.make(),
  shellBuilder: NodeJsShellBuilder.make(),
  envFilter: NodeJsEnvFilter.make(),
  hooks: NodeJsHooks.make(),
}

suite("Engine Integration", () => {
  testAsync("run: creates output file from template EJS rendering", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "component.ejs.t"),
      directives: [Template.To("src/Component.tsx")],
      body: "export const <%= Name %> = () => <div><%= name %></div>",
    }

    let gen: Discovery.generator = {
      name: "component",
      path: tmpDir,
      templates: [template],
    }

    Engine.run(
      ~generator=gen,
      ~name="Button",
      ~cliAttributes=Dict.make(),
      ~outputDir,
      ~force=true,
      ~deps,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(r) => {
          assert_eq(r.classification, "component")
          assert_true(r.filesCreated >= 1)

          // Verify rendered output
          let outputFile = NodeJs.Path.join(outputDir, "src/Component.tsx")
          NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"})
          ->Promise.then(content => {
            assert_true(String.includes(content, "Button"))
            assert_true(String.includes(content, "button"))
            assert_true(String.includes(content, "export const Button"))
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      | Error(_) => {
          assert_false(true)
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        }
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: force=true overwrites existing output file", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let outputFile = NodeJs.Path.join(outputDir, "out.txt")

    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "t.ejs.t"),
      directives: [Template.To("out.txt")],
      body: "new-content",
    }

    let gen: Discovery.generator = {
      name: "test",
      path: tmpDir,
      templates: [template],
    }

    // Pre-create the output file with different content
    NodeJs.Fs.mkdir(outputDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputFile, "old-content"))
    ->Promise.then(_ =>
      Engine.run(
        ~generator=gen,
        ~name="Test",
        ~cliAttributes=Dict.make(),
        ~outputDir,
        ~force=true,
        ~deps,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(r) => {
          assert_eq(r.filesCreated, 1)

          NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"})
          ->Promise.then(content => {
            // Should be overwritten with new content
            assert_true(String.includes(content, "new-content"))
            assert_false(String.includes(content, "old-content"))
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      | Error(_) => {
          assert_false(true)
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        }
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: executes tool directive when shell config has matching tool", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "t.ejs.t"),
      directives: [
        Template.To("out.txt"),
        Template.Tool("lint"),
      ],
      body: "content",
    }

    let gen: Discovery.generator = {
      name: "test-tool",
      path: tmpDir,
      templates: [template],
    }

    let cfg: Config.config = {
      shell: {enabled: true, tools: [{name: "lint", command: "echo", args: ["ok"]}]},
    }

    Engine.run(
      ~generator=gen,
      ~name="Test",
      ~cliAttributes=Dict.make(),
      ~outputDir,
      ~force=true,
      ~config=cfg,
      ~deps,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(r) => {
          assert_true(r.filesCreated >= 1)
          // Tool should have been executed
          assert_true(r.commandsExecuted >= 1)
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

  testAsync("run: with UnlessExists template skips existing file", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let outputFile = NodeJs.Path.join(outputDir, "existing.txt")

    let template: Template.template = {
      sourcePath: NodeJs.Path.join(tmpDir, "t.ejs.t"),
      directives: [Template.To("existing.txt"), Template.UnlessExists],
      body: "should-not-appear",
    }

    let gen: Discovery.generator = {
      name: "test-ue",
      path: tmpDir,
      templates: [template],
    }

    // Pre-create the output file
    NodeJs.Fs.mkdir(outputDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputFile, "original-content"))
    ->Promise.then(_ =>
      Engine.run(
        ~generator=gen,
        ~name="Test",
        ~cliAttributes=Dict.make(),
        ~outputDir,
        ~force=true,
        ~deps,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(r) => {
          // File should NOT have been created (unlessExists skips it)
          assert_eq(r.filesCreated, 0)

          NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"})
          ->Promise.then(content => {
            // Original content preserved
            assert_true(String.includes(content, "original-content"))
            assert_false(String.includes(content, "should-not-appear"))
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      | Error(_) => {
          assert_false(true)
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        }
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate create-res-project: produces runnable project structure", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    // Pre-create package.json in output dir (pre-hook reads it)
    NodeJs.Fs.mkdir(outputDir, ~options={recursive: true})
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        NodeJs.Path.join(outputDir, "package.json"),
        "{\"name\": \"smoke-app\"}\n",
      )
    )
    // Discover the real create-res-project generator from examples/
    ->Promise.then(_ =>
      Discovery.discoverGenerators(
        ~fs=deps.fs,
        ~path=NodeJsPath.make(),
        ~yamlParser=deps.yamlParser,
        ~searchPaths=["examples"],
        (),
      )
    )
    ->Promise.then(gens => {
      switch Discovery.findByClassificationMeta(gens, "create-res-project") {
      | None =>
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        assert_false(true)
        resolve()
        Promise.resolve()
      | Some(meta) =>
        Discovery.loadGeneratorTemplates(~fs=deps.fs, ~path=NodeJsPath.make(), meta.path)
        ->Promise.then(templates => {
          let generator: Discovery.generator = {
            name: meta.name,
            path: meta.path,
            templates,
            manifest: ?meta.manifest,
          }
          EngineOrchestrator.run(
            ~generator,
            ~name="smoke-app",
            ~cliAttributes=Dict.make(),
            ~outputDir,
            ~force=true,
            ~deps,
          )
        ->Promise.then(result => {
          switch result {
          | Error(e) => {
              NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
              Console.error("Engine error: " ++ e.message)
              assert_false(true)
              resolve()
              Promise.resolve()
            }
          | Ok(_r) => {
              // Assert Main.res greeting
              let mainResPath = NodeJs.Path.join(outputDir, "src/Main.res")
              NodeJs.Fs.readFile(mainResPath, ~options={encoding: "utf8"})
              ->Promise.then(mainContent => {
                assert_true(String.includes(mainContent, "Hello, smoke-app!"))

                // Assert rescript.json name
                let rescriptJsonPath = NodeJs.Path.join(outputDir, "rescript.json")
                NodeJs.Fs.readFile(rescriptJsonPath, ~options={encoding: "utf8"})
                ->Promise.then(rjContent => {
                  assert_true(String.includes(rjContent, "\"name\"") && String.includes(rjContent, "smoke-app"))

                  // Assert rolldown.config.mjs is generic (no VanRs/vanrs)
                  let rolldownPath = NodeJs.Path.join(outputDir, "rolldown.config.mjs")
                  NodeJs.Fs.readFile(rolldownPath, ~options={encoding: "utf8"})
                  ->Promise.then(rollContent => {
                    assert_false(String.includes(rollContent, "VanRs") || String.includes(rollContent, "vanrs"))

                    // Assert package.json post-hook mutations via string search
                    // (setup-rescript.mjs adds deps.rescript, scripts.res:build,
                    //  engines.node, bin.smoke-app)
                    let pkgJsonPath = NodeJs.Path.join(outputDir, "package.json")
                    NodeJs.Fs.readFile(pkgJsonPath, ~options={encoding: "utf8"})
                    ->Promise.then(pkgContent => {
                      let hasRescript = String.includes(pkgContent, "\"rescript\"")
                      let hasResBuild = String.includes(pkgContent, "\"res:build\"")
                      let hasNodeEngines = String.includes(pkgContent, "\"node\"")
                      let hasBin = String.includes(pkgContent, "\"smoke-app\"") &&
                        String.includes(pkgContent, "dist/main.mjs")
                      assert_true(hasRescript && hasResBuild && hasNodeEngines && hasBin)
                      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
                      resolve()
                      Promise.resolve()
                    })
                  })
                })
              })
            }
          }
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
        })
      }
    })
    ->ignore
  })
})
