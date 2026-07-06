// test/ConfigStore_test.res — integration tests for ConfigStore save/load operations

open TestHelpers
open ConfigStore
open ConfigTypes

suite("ConfigStore", () => {
  testAsync("saveGlobalAtPath: writes config.yaml to specified path", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let configPath = NodeJs.Path.join(tmpDir, "config.yaml")
    let cfg: globalConfig = {
      templates: ["/opt/templates"],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      registry: [],
    }

    saveGlobalAtPath(~fs, ~path=pathAdapter, ~configPath, cfg)
    ->Promise.then(result => {
      switch result {
      | Ok(()) => NodeJs.Fs.readFile(configPath, ~options={encoding: "utf8"})
      | Error(_) => {
          assert_false(true)
          Promise.resolve("")
        }
      }
    })
    ->Promise.then(content => {
      assert_true(String.includes(content, "templates:"))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("loadGlobal: returns None when file does not exist", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let nonExistentPath = NodeJs.Path.join(tmpDir, "nonexistent")
    loadGlobal(~fs, ~path=pathAdapter, ~homeDir=nonExistentPath)
    ->Promise.then(result => {
      switch result {
      | Ok(None) => assert_true(true)
      | _ => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("loadGlobal: round-trip save then load", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let cfg: globalConfig = {
      templates: ["/opt/team", "/home/user/templates"],
      forceOverwrite: false,
      dryRun: false,
      timeout: 30,
      defaultAttributes: Dict.make(),
      registry: [],
    }

    saveGlobal(~fs, ~path=pathAdapter, ~homeDir=tmpDir, cfg)
    ->Promise.then(writeResult => {
      switch writeResult {
      | Ok(()) => loadGlobal(~fs, ~path=pathAdapter, ~homeDir=tmpDir)
      | Error(_e) => {
          assert_false(true)
          Promise.resolve(Error("write failed"))
        }
      }
    })
    ->Promise.then(result => {
      switch result {
      | Ok(Some(loaded)) => {
          assert_eq(Array.length(loaded.templates), 2)
          // WS4: allowDangerousCommands removed from globalConfig.
          assert_eq(loaded.timeout, 30)
        }
      | _ => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("loadFrom: returns None when no .blueprint.yaml in directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    loadFrom(~fs, ~path=pathAdapter, tmpDir)
    ->Promise.then(result => {
      switch result {
      | Ok(None) => assert_true(true)
      | _ => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("loadFrom: returns Some config when .blueprint.yaml exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let yaml = "output: dist\nhooks:\n  pre_generate:\n    command: echo start\n"
    NodeJs.Fs.writeFile(NodeJs.Path.join(tmpDir, ".blueprint.yaml"), yaml)
    ->Promise.then(_ => loadFrom(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(result => {
      switch result {
      | Ok(Some(cfg)) => {
          assert_eq(cfg.output, Some("dist"))
          switch cfg.hooks {
          | Some(h) => assert_eq(h.preGenerate->Option.map(cmd => cmd.command), Some("echo start"))
          | None => assert_false(true)
          }
        }
      | _ => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("saveGlobal: saves to correct global path", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let cfg: globalConfig = {
      templates: ["/opt"],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      registry: [],
    }

    saveGlobal(~fs, ~path=pathAdapter, ~homeDir=tmpDir, cfg)
    ->Promise.then(result => {
      switch result {
      | Ok(()) => {
          let expectedPath = NodeJs.Path.join(NodeJs.Path.join(NodeJs.Path.join(tmpDir, ".config"), "blueprint"), "config.yaml")
          NodeJs.Fs.fileExists(expectedPath)
          ->Promise.then(exists => {
            assert_true(exists)
            resolve()
            Promise.resolve()
          })
        }
      | Error(_) => {
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      }
    })
    ->ignore
  })
})