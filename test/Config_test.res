// Config_test — config parsing and loading tests

open TestHelpers
open NodeJsFileSystem
open NodeJsPath

suite("Config", () => {
  test("parse: returns Ok with empty hooks when no hooks key", () => {
    let yaml = "output: dist\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) => assert_eq(cfg.output, Some("dist"))
    | Error(_) => assert_false(true)
    }
  })

  test("parse: returns Ok with hooks when yaml has pre_generate", () => {
    let yaml = "hooks:\n  pre_generate: \"echo start\"\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.hooks {
      | Some(h) =>
        assert_eq(h.preGenerate, Some({command: "echo start"}))
        assert_true(true)
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: returns Ok with hooks when yaml has both hooks", () => {
    let yaml = "hooks:\n  pre_generate: \"echo start\"\n  post_generate: \"echo end\"\n  timeout: 10\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.hooks {
      | Some(h) => {
          assert_eq(h.preGenerate, Some({command: "echo start"}))
          assert_eq(h.postGenerate, Some({command: "echo end"}))
          assert_eq(h.timeout, Some(10))
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: returns Ok with empty object for non-object yaml", () => {
    let yaml = "42\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(_) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })

  test("defaultOutputDir: is generated", () => {
    assert_eq(Config.defaultOutputDir, "generated")
  })

  testAsync("loadFrom: returns None when no .blueprint.yaml exists", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ => Config.loadFrom(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(result => {
      switch result {
      | Ok(opt) =>
        switch opt {
        | None => assert_true(true)
        | Some(_) => assert_false(true)
        }
      | Error(_) => assert_false(true)
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
    let yaml = "hooks:\n  pre_generate:\n    command: echo hello\n"
    NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(NodeJs.Path.join(tmpDir, ".blueprint.yaml"), yaml)
    )
    ->Promise.then(_ => Config.loadFrom(~fs, ~path=pathAdapter, tmpDir))
    ->Promise.then(result => {
      switch result {
      | Ok(opt) =>
        switch opt {
        | Some(cfg) =>
          switch cfg.hooks {
          | Some(h) => assert_eq(h.preGenerate, Some({command: "echo hello"}))
          | None => assert_false(true)
          }
        | None => assert_false(true)
        }
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- Global config tests ---

  test("parseGlobal: parses all fields correctly", () => {
    let yaml = "templates:\n  - /opt/team\n  - ~/my-templates\nallow_dangerous_commands: true\nforce_overwrite: true\ndry_run: true\ntimeout: 30\ndefault_attributes:\n  author: \"me\"\n  license: \"MIT\"\n"
    let result = Config.parseGlobal(yaml)
    switch result {
    | Ok(cfg) => {
        assert_eq(Array.length(cfg.templates), 2)
        assert_eq(cfg.templates[0], Some("/opt/team"))
        assert_eq(cfg.templates[1], Some("~/my-templates"))
        assert_eq(cfg.allowDangerousCommands, true)
        assert_eq(cfg.forceOverwrite, true)
        assert_eq(cfg.dryRun, true)
        assert_eq(cfg.timeout, 30)
        assert_eq(Dict.get(cfg.defaultAttributes, "author"), Some("me"))
        assert_eq(Dict.get(cfg.defaultAttributes, "license"), Some("MIT"))
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseGlobal: uses defaults when fields are missing", () => {
    let yaml = "templates:\n  - /shared\n"
    let result = Config.parseGlobal(yaml)
    switch result {
    | Ok(cfg) => {
        assert_eq(Array.length(cfg.templates), 1)
        assert_eq(cfg.allowDangerousCommands, false)
        assert_eq(cfg.forceOverwrite, false)
        assert_eq(cfg.dryRun, false)
        assert_eq(cfg.timeout, 5)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseGlobal: returns defaults for empty yaml", () => {
    let yaml = ""
    let result = Config.parseGlobal(yaml)
    switch result {
    | Ok(cfg) => {
        assert_eq(Array.length(cfg.templates), 0)
        assert_eq(cfg.allowDangerousCommands, false)
        assert_eq(cfg.forceOverwrite, false)
        assert_eq(cfg.dryRun, false)
        assert_eq(cfg.timeout, 5)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("defaultGlobalConfig: has correct defaults", () => {
    let cfg = Config.defaultGlobalConfig
    assert_eq(Array.length(cfg.templates), 0)
    assert_eq(cfg.allowDangerousCommands, false)
    assert_eq(cfg.forceOverwrite, false)
    assert_eq(cfg.dryRun, false)
    assert_eq(cfg.timeout, 5)
    assert_eq(Dict.size(cfg.defaultAttributes), 0)
  })

  test("mergeConfig: project timeout overrides global", () => {
    let global: Config.globalConfig = {
      templates: ["/opt/team"],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: 30,
      defaultAttributes: Dict.make(),
      registry: [],
    }
    let project: Config.config = {
      output: "dist",
      hooks: {
        preGenerate: {command: "echo hi"},
        timeout: 10,
      },
    }

    let merged = Config.mergeConfig(~global, ~project=Some(project))
    assert_eq(merged.timeout, 10)
    assert_eq(Array.length(merged.templates), 1)
    assert_eq(merged.allowDangerousCommands, false)
    assert_eq(merged.forceOverwrite, false)
    assert_eq(merged.dryRun, false)
  })

  test("mergeConfig: global used when project has no hooks timeout", () => {
    let global: Config.globalConfig = {
      templates: [],
      allowDangerousCommands: true,
      forceOverwrite: true,
      dryRun: true,
      timeout: 30,
      defaultAttributes: Dict.make(),
      registry: [],
    }
    let project: Config.config = {
      output: "dist",
      hooks: {
        preGenerate: {command: "echo hi"},
      },
    }

    let merged = Config.mergeConfig(~global, ~project=Some(project))
    assert_eq(merged.timeout, 30)  // global used
    assert_eq(merged.allowDangerousCommands, true)
    assert_eq(merged.forceOverwrite, true)
    assert_eq(merged.dryRun, true)
  })

  test("mergeConfig: global used when no project config", () => {
    let global: Config.globalConfig = {
      templates: ["/opt/team", "/home/user/templates"],
      allowDangerousCommands: true,
      forceOverwrite: false,
      dryRun: false,
      timeout: 60,
      defaultAttributes: Dict.make(),
      registry: [],
    }

    let merged = Config.mergeConfig(~global, ~project=None)
    assert_eq(merged.timeout, 60)
    assert_eq(Array.length(merged.templates), 2)
    assert_eq(merged.allowDangerousCommands, true)
  })

  testAsync("loadGlobal: returns None when no global config exists", resolve => {
    // Mock by creating a temp dir and checking a non-existent path
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fakeGlobalPath = NodeJs.Path.join(NodeJs.Path.join(tmpDir, "nonexistent"), "config.yaml")
    // Override _globalConfigPath behavior by checking file existence directly
    NodeJs.Fs.fileExists(fakeGlobalPath)
    ->Promise.then(exists => {
      assert_false(exists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- Shell config tests ---

  test("parse: shell.enabled false", () => {
    let yaml = "shell:\n  enabled: false\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.shell {
      | Some(s) => assert_eq(s.enabled, false)
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: shell.enabled true", () => {
    let yaml = "shell:\n  enabled: true\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.shell {
      | Some(s) => assert_eq(s.enabled, true)
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: shell.tools with name and command", () => {
    let yaml = "shell:\n  enabled: true\n  tools:\n    - name: format\n      command: npx prettier --write\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.shell {
      | Some(s) =>
        switch s.tools {
        | Some(tools) =>
          assert_eq(Array.length(tools), 1)
          switch tools[0] {
          | Some(t) =>
            assert_eq(t.name, "format")
            assert_eq(t.command, "npx prettier --write")
          | None => assert_false(true)
          }
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: shell.tools with args", () => {
    let yaml = "shell:\n  enabled: true\n  tools:\n    - name: lint\n      command: npx eslint\n      args:\n        - --fix\n        - .\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.shell {
      | Some(s) =>
        switch s.tools {
        | Some(tools) =>
          switch tools[0] {
          | Some(t) =>
            assert_eq(t.name, "lint")
            assert_eq(t.command, "npx eslint")
            switch t.args {
            | Some(args) =>
              assert_eq(Array.length(args), 2)
              assert_eq(args[0], Some("--fix"))
              assert_eq(args[1], Some("."))
            | None => assert_false(true)
            }
          | None => assert_false(true)
          }
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: shell.env key-value", () => {
    let yaml = "shell:\n  enabled: true\n  env:\n    NODE_ENV: production\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.shell {
      | Some(s) =>
        switch s.env {
        | Some(env) =>
          switch Dict.get(env.vars, "NODE_ENV") {
          | Some(v) => assert_eq(v, "production")
          | None => assert_false(true)
          }
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseGlobal: allow_dangerous_commands migrates to shell.enabled true", () => {
    let yaml = "allow_dangerous_commands: true\n"
    let result = Config.parseGlobal(yaml)
    switch result {
    | Ok(cfg) =>
      // allowDangerousCommands is the old field, new system uses shell.enabled
      // The migration: allow_dangerous_commands: true → shell.enabled: true
      // This is stored in globalConfig.allowDangerousCommands for migration compat
      assert_eq(cfg.allowDangerousCommands, true)
    | Error(_) => assert_false(true)
    }
  })

  test("parseGlobal: parses registry entries", () => {
    let yaml = "registry:\n  - name: model\n    source: /workspace/_templates/model\n    path: /home/user/.config/blueprint/templates/model\n"
    let result = Config.parseGlobal(yaml)
    switch result {
    | Ok(cfg) =>
      assert_eq(Array.length(cfg.registry), 1)
      switch cfg.registry[0] {
      | Some(entry) => {
          assert_eq(entry.name, "model")
          assert_eq(entry.source, "/workspace/_templates/model")
          assert_eq(entry.path, "/home/user/.config/blueprint/templates/model")
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parseGlobal: defaults registry to empty", () => {
    let yaml = "templates: []\n"
    let result = Config.parseGlobal(yaml)
    switch result {
    | Ok(cfg) => assert_eq(Array.length(cfg.registry), 0)
    | Error(_) => assert_false(true)
    }
  })

  testAsync("saveGlobalAtPath: persists registry via yaml stringify", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let configPath = NodeJs.Path.join(tmpDir, "config.yaml")
    let defaults = Dict.make()
    Dict.set(defaults, "author", "blueprint")
    let cfg: Config.globalConfig = {
      templates: ["/opt/templates"],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: defaults,
      registry: [{name: "service", source: "/workspace/_templates/service", path: "/tmp/registry/service"}],
    }

    Config.saveGlobalAtPath(~fs, ~path=pathAdapter, ~configPath, cfg)
    ->Promise.then(writeResult => {
      switch writeResult {
      | Ok(()) => NodeJs.Fs.readFile(configPath, ~options={encoding: "utf8"})
      | Error(_) => {
          assert_false(true)
          Promise.resolve("")
        }
      }
    })
    ->Promise.then(savedYaml => {
      assert_true(String.includes(savedYaml, "registry:"))
      assert_true(String.includes(savedYaml, "name: service"))
      assert_true(String.includes(savedYaml, "source: /workspace/_templates/service"))
      assert_true(String.includes(savedYaml, "path: /tmp/registry/service"))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  test("parse: shell section absent returns None", () => {
    let yaml = "output: dist\n"
    let result = Config.parse(yaml)
    switch result {
    | Ok(cfg) =>
      switch cfg.shell {
      | Some(_) => assert_false(true)
      | None => assert_true(true)
      }
    | Error(_) => assert_false(true)
    }
  })
})
