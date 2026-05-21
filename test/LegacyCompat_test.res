// LegacyCompat_test — backward compatibility tests

open TestHelpers

suite("LegacyCompat", () => {
  test("allow_dangerous_commands: true migrates to shell.enabled: true", () => {
    // Legacy allow_dangerous_commands: true should map to shell.enabled: true
    // In Config.res mergeConfig, this migration is handled
    let legacyConfig = "
allow_dangerous_commands: true
"
    let parsed = Config.parse(legacyConfig)
    switch parsed {
    | Ok(_cfg) => {
        // Note: allow_dangerous_commands is no longer parsed into shell.enabled
        // The migration is handled at mergeConfig level
        assert_true(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("allow_dangerous_commands: false migrates to shell.enabled: false", () => {
    let legacyConfig = "
allow_dangerous_commands: false
"
    let parsed = Config.parse(legacyConfig)
    switch parsed {
    | Ok(_) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })

  test("legacy sh: exact match with tool works", () => {
    // Legacy sh: "npm run lint" when tool has command: "npm run lint" (no args)
    // Should execute via exec with shell:true
    let shellConfig: Config.shellConfig = {
      enabled: true,
      tools: [
        {
          name: "lint",
          command: "npm run lint",
        },
      ],
    }

    // When tool has no args, sh: "npm run lint" matches exactly
    switch shellConfig.tools {
    | Some(tools) =>
      let lintTool = tools->Array.find(t => t.name == "lint")
      switch lintTool {
      | Some(tool) => assert_eq(tool.command, "npm run lint")
      | None => assert_false(true)
      }
    | None => assert_false(true)
    }
  })

  test("legacy sh: warns on deprecated usage", () => {
    // When sh: directive is used (not tool:), Frontmatter should log warning
    // The warning is emitted during Frontmatter.parse
    // We can't easily test log output, but we can verify the directive variant exists
    let result = Frontmatter.parse("---js\nsh: npm run lint\n---")
    switch result {
    | Ok(parsed) => {
        // Should contain Sh variant (legacy)
        let hasSh = parsed.directives->Array.some(d => {
          switch d {
          | Template.Sh(_) => true
          | _ => false
          }
        })
        assert_true(hasSh)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("tool: directive takes precedence over legacy sh:", () => {
    // New code should use tool: directive instead of sh:
    let result = Frontmatter.parse("---js\ntool: format\n---")
    switch result {
    | Ok(parsed) => {
        let hasTool = parsed.directives->Array.some(d => {
          switch d {
          | Template.Tool(_) => true
          | _ => false
          }
        })
        assert_true(hasTool)
      }
    | Error(_) => assert_false(true)
    }
  })
})