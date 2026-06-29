// test/ConfigTypes_test.res
open TestHelpers
open ConfigTypes

suite("ConfigTypes", () => {
  test("defaultGlobalConfig: has correct field values", () => {
    let cfg = ConfigTypes.defaultGlobalConfig
    assert_eq(Array.length(cfg.templates), 0)
    // WS4: `allowDangerousCommands` removed — ExecPolicy is the authority.
    assert_eq(cfg.forceOverwrite, false)
    assert_eq(cfg.dryRun, false)
    assert_eq(cfg.timeout, 5)
    assert_eq(Dict.size(cfg.defaultAttributes), 0)
    assert_eq(Array.length(cfg.registry), 0)
  })

  test("shellTool: name and command required", () => {
    let tool: ConfigTypes.shellTool = {name: "format", command: "npx prettier"}
    assert_eq(tool.name, "format")
    assert_eq(tool.command, "npx prettier")
    assert_eq(tool.args, None)
  })

  test("shellTool: args provided", () => {
    let tool: ConfigTypes.shellTool = {name: "lint", command: "npx eslint", args: ["--fix", "."]}
    switch tool.args {
    | Some(args) => assert_eq(Array.length(args), 2)
    | None => assert_false(true)
    }
  })

  test("scriptDef: all fields", () => {
    let script: ConfigTypes.scriptDef = {name: "build", path: "./scripts/build.sh", args: ["--prod"]}
    switch script.args {
    | Some(args) => assert_eq(Array.length(args), 1)
    | None => assert_false(true)
    }
  })

  test("hooksConfig: pre and post optional", () => {
    let hooks: ConfigTypes.hooksConfig = {preGenerate: {command: "echo start"}, postGenerate: {command: "echo end"}, timeout: 10}
    assert_eq(hooks.preGenerate->Option.isSome, true)
    assert_eq(hooks.postGenerate->Option.isSome, true)
    assert_eq(hooks.timeout, Some(10))
  })

  test("config: project-level", () => {
    let cfg: ConfigTypes.config = {
      hooks: {preGenerate: {command: "echo start"}, timeout: 5},
      output: "dist",
      shell: {enabled: true},
    }
    assert_eq(cfg.output, Some("dist"))
    assert_eq(cfg.shell->Option.map(s => s.enabled), Some(true))
  })

  test("templateSource: all fields", () => {
    let ts: ConfigTypes.templateSource = {name: "model", source: "/opt/templates", path: "/home/user/.blueprint/templates/model"}
    assert_eq(ts.name, "model")
    assert_eq(ts.source, "/opt/templates")
    assert_eq(ts.path, "/home/user/.blueprint/templates/model")
  })

  test("mergedConfig: shell merged correctly", () => {
    // WS4: `allowDangerousCommands` removed from mergedConfig.
    let merged: ConfigTypes.mergedConfig = {
      templates: ["/opt"],
      forceOverwrite: false,
      dryRun: false,
      timeout: 10,
      defaultAttributes: Dict.make(),
      shell: {enabled: true, tools: [{name: "fmt", command: "npx prettier"}]},
    }
    assert_eq(merged.timeout, 10)
    assert_eq(merged.shell->Option.map(s => s.enabled), Some(true))
    assert_eq(merged.shell->Option.flatMap(s => s.tools)->Option.map(a => Array.length(a)), Some(1))
  })
})