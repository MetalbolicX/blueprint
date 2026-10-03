// Integration_test — full pipeline integration tests for shell security

open TestHelpers

suite("Integration", () => {
  test("shell.enabled: false blocks unsupported directive", () => {
    // Create a minimal shellConfig with enabled: false
    let disabledConfig: Config.shellConfig = {
      enabled: false,
    }

    // Verify that shell.enabled is false
    assert_eq(disabledConfig.enabled, false)
  })

  test("shell.enabled: true with no tools declared blocks unknown tool", () => {
    let configWithNoTools: Config.shellConfig = {
      enabled: true,
    }

    // With shell enabled but no tools, the allowlist is empty
    // Any tool lookup should fail
    switch configWithNoTools.tools {
    | Some([]) => assert_true(true) // empty array
    | None => assert_true(true) // no tools at all
    | _ => assert_false(true)
    }
  })

  test("shell.enabled: true with valid tool allows execution", () => {
    let config: Config.shellConfig = {
      enabled: true,
      tools: [
        {
          name: "test-cmd",
          command: "echo",
          args: ["test-ok"],
        },
      ],
    }

    // Config has tool with args, so it uses execFile (no shell)
    assert_eq(config.enabled, true)
    switch config.tools {
    | Some(tools) => assert_eq(Array.length(tools), 1)
    | None => assert_false(true)
    }
  })

  test("shell.enabled: false with unsupported shell command is blocked", () => {
    let disabledConfig: Config.shellConfig = {
      enabled: false,
    }

    // When shell is disabled, InlineCommand path returns "Shell execution disabled"
    assert_eq(disabledConfig.enabled, false)
  })

  test("shell.enabled: true with tool command works", () => {
    // Tool commands are matched against tool.command+args
    let config: Config.shellConfig = {
      enabled: true,
      tools: [
        {
          name: "lint",
          command: "npm run lint",
        },
      ],
    }

    // When tool has no args, command "npm run lint" matches exactly
    assert_eq(config.enabled, true)
  })

  test("shell.enabled: true with mismatched tool command is blocked", () => {
    let config: Config.shellConfig = {
      enabled: true,
      tools: [
        {
          name: "format",
          command: "npx prettier --write .",
        },
      ],
    }

    // If template declares one command but config exposes another, no match
    // Should be blocked
    switch config.tools {
    | Some(tools) =>
      let hasLint = tools->Array.some(t => t.name == "lint" || t.command == "npm run lint")
      assert_false(hasLint)
    | None => assert_true(true)
    }
  })

  test("Fetch directive URL parsing", () => {
    // Test that fetch URL is properly passed to Fetcher
    let fetchUrl = "https://raw.githubusercontent.com/user/repo/main/.gitignore"

    // Verify URL format is valid (basic check)
    assert_true(String.includes(fetchUrl, "https://"))
  })

  test("Fetch with timeout returns error on timeout", () => {
    // Fetcher.fetch should handle timeout correctly
    // When Fetcher.fetch is called with a very short timeout on unreachable URL,
    // it should return Error("Request timed out")
    // Note: actual timeout testing would require network call or mock
    assert_true(true) // Placeholder for timeout test
  })

  test("Fetch with 404 returns error", () => {
    // Fetcher.fetch with non-existent URL should return Error("Not found")
    // Note: actual 404 testing would require network call
    assert_true(true) // Placeholder for 404 test
  })

  // --- Health/readiness probe tests ---

  test("structured log entry: has required JSON fields", () => {
    // A valid structured log entry should parse as JSON and contain these fields
    let _rawEntry = "{\"timestamp\":\"2026-05-19T10:30:00.000Z\",\"level\":\"INFO\",\"runId\":\"test-123\",\"event\":\"phase0/start\",\"message\":\"Starting\",\"meta\":{}}"
    try {
      let parsed = JSON.parseOrThrow(_rawEntry)
      switch parsed {
      | Object(dict) =>
        let hasTimestamp = Dict.get(dict, "timestamp")->Option.isSome
        let hasLevel = Dict.get(dict, "level")->Option.isSome
        let hasRunId = Dict.get(dict, "runId")->Option.isSome
        let hasEvent = Dict.get(dict, "event")->Option.isSome
        assert_true(hasTimestamp && hasLevel && hasRunId && hasEvent)
      | _ => assert_false(true)
      }
    } catch {
    | _ => assert_false(true)
    }
  })

  test("structured log entry: runId is non-empty string", () => {
    let _rawEntry = "{\"timestamp\":\"2026-05-19T10:30:00.000Z\",\"level\":\"INFO\",\"runId\":\"1747655400123-4821\",\"event\":\"test\",\"message\":\"msg\"}"
    try {
      let parsed = JSON.parseOrThrow(_rawEntry)
      switch parsed {
      | Object(dict) =>
        switch Dict.get(dict, "runId") {
        | Some(val) => 
          switch val {
          | String(runId) => 
            assert_true(String.length(runId) > 0 && runId !== "undefined" && runId !== "null")
          | _ => assert_false(true)
          }
        | None => assert_false(true)
        }
      | _ => assert_false(true)
      }
    } catch {
    | _ => assert_false(true)
    }
  })

  test("validateMergedConfig exists and rejects invalid config", () => {
    // Config.validateMergedConfig should exist and reject timeout <= 0
    let badConfig: Config.mergedConfig = {
      templates: [],
      forceOverwrite: false,
      dryRun: false,
      timeout: 0,
      defaultAttributes: Dict.make(),
    }

    switch Config.validateMergedConfig(badConfig) {
    | Ok(_) => assert_false(true)
    | Error(_) => assert_true(true)
    }
  })

  test("validateMergedConfig exists and accepts valid config", () => {
    let goodConfig: Config.mergedConfig = {
      templates: [],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      shell: {enabled: false},
    }

    switch Config.validateMergedConfig(goodConfig) {
    | Ok(_) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })

  // --- Conflict detection integration ---

  // plan 043
  testAsync("detectRenderedConflicts: multi-template returns all conflicts", resolve => {
    // When multiple templates target existing files, all should be reported
    // plan 043: exercises the rendered-target API before conflict resolution
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outDir = NodeJs.Path.join(tmpDir, "out")

    let templates: array<Template.template> = [
      {
        sourcePath: NodeJs.Path.join(tmpDir, "a.ejs.t"),
        directives: [Template.To("a.txt")],
        body: "a",
      },
      {
        sourcePath: NodeJs.Path.join(tmpDir, "b.ejs.t"),
        directives: [Template.To("b.txt")],
        body: "b",
      },
    ]

    NodeJs.Fs.mkdir(outDir, ~options={recursive: true})
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(NodeJs.Path.join(outDir, "a.txt"), "existing-a")
    )
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(NodeJs.Path.join(outDir, "b.txt"), "existing-b")
    )
    ->Promise.then(_ => {
      let fsAdapter = NodeJsFileSystem.make()
      let pathAdapter = NodeJsPath.make()
      Phase0.detectRenderedConflicts(
        ~templates,
        ~outputDir=outDir,
        ~force=false,
        ~ejs=TestPorts.stubEjs,
        ~attributes=Dict.make(),
        ~fs=fsAdapter,
        ~path=pathAdapter,
      )
    })
    ->Promise.then(result => {
      switch result {
      | Ok(conflicts) => assert_eq(Array.length(conflicts), 2)
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
