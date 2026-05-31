// Utils_test — Utils testing

open TestHelpers

let deps: Ports.deps = {
  fs: NodeJsFileSystem.make(),
  path: NodeJsPath.make(),
  process: NodeJsProcess.make(),
  shell: NodeJsShell.make(),
  interactiveIO: NodeJsInteractiveIO.make(()),
  argParser: NodeJsArgParser.make(),
}

suite("Utils", () => {
  test("globalTemplateRegistryRoot: ends with correct path", () => {
    let result = Utils.globalTemplateRegistryRoot(~deps)
    assert_true(String.endsWith(result, deps.path.join(".config", deps.path.join("blueprint", "templates"))))
  })

  test("globalConfigPath: ends with correct path", () => {
    let result = Utils.globalConfigPath(~deps)
    assert_true(String.endsWith(result, deps.path.join(".config", deps.path.join("blueprint", "config.yaml"))))
  })

  test("buildGenerateSearchPaths: returns prioritized list without duplicates", () => {
    let projectPaths = ["/project/.blueprint"]
    let registry: array<Config.templateSource> = [
      {name: "a", source: "src", path: "/registry/a/template"},
      {name: "b", source: "src", path: "/registry/b/template"},
      {name: "a_dup", source: "src", path: "/registry/a/template2"}
    ]
    let globalTemplates = ["/global/.blueprint"]
    
    let result = Utils.buildGenerateSearchPaths(~deps, ~projectPaths, ~registry, ~globalTemplates)
    
    // Expected: project path, unique registry paths, global path
    assert_eq(Array.length(result), 4)
    assert_eq(result[0], Some("/project/.blueprint"))
    assert_eq(result[1], Some("/registry/a"))
    assert_eq(result[2], Some("/registry/b"))
    assert_eq(result[3], Some("/global/.blueprint"))
  })
})
