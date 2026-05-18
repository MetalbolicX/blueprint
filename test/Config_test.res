// Config_test — config parsing and loading tests

open TestHelpers

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
        assert_eq(h.preGenerate, Some("echo start"))
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
          assert_eq(h.preGenerate, Some("echo start"))
          assert_eq(h.postGenerate, Some("echo end"))
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
    NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ => Config.loadFrom(tmpDir))
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
    let yaml = "hooks:\n  pre_generate: \"echo hello\"\n"
    NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(NodeJs.Path.join(tmpDir, ".blueprint.yaml"), yaml)
    )
    ->Promise.then(_ => Config.loadFrom(tmpDir))
    ->Promise.then(result => {
      switch result {
      | Ok(opt) =>
        switch opt {
        | Some(cfg) =>
          switch cfg.hooks {
          | Some(h) => assert_eq(h.preGenerate, Some("echo hello"))
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
})
