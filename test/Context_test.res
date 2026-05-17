// Context_test — name variant generation and merge priority tests

open TestHelpers

suite("Context", () => {
  test("makeNameVariants: basic", () => {
    let variants = Context.makeNameVariants("HelloWorld")
    assert_eq(variants.name, "hello_world")
    assert_eq(variants.pascalName, "HelloWorld")
    assert_eq(variants.names, "hello_worlds")
    assert_eq(variants.pluralPascalName, "HelloWorlds")
  })

  test("makeNameVariants: snake_case input", () => {
    let variants = Context.makeNameVariants("hello_world")
    assert_eq(variants.pascalName, "HelloWorld")
    assert_eq(variants.names, "hello_worlds")
  })

  test("makeNameVariants: kebab-case input", () => {
    let variants = Context.makeNameVariants("hello-world")
    assert_eq(variants.pascalName, "HelloWorld")
  })

  test("mergeAttributes: CLI overrides prompts", () => {
    let cli = Dict.fromArray([("name", "cliName")])
    let prompts = Dict.fromArray([("name", "promptName")])
    let defaults = Dict.make()
    let nv = Context.makeNameVariants("BaseName")

    let merged = Context.mergeAttributes(
      ~cliAttributes=cli,
      ~promptAnswers=prompts,
      ~manifestDefaults=defaults,
      ~nameVariants=nv,
    )

    assert_eq(Dict.get(merged, "name"), Some("cliName"))
  })

  test("mergeAttributes: prompts override defaults", () => {
    let cli = Dict.make()
    let prompts = Dict.fromArray([("name", "promptName")])
    let defaults = Dict.fromArray([("name", "defaultName")])
    let nv = Context.makeNameVariants("BaseName")

    let merged = Context.mergeAttributes(
      ~cliAttributes=cli,
      ~promptAnswers=prompts,
      ~manifestDefaults=defaults,
      ~nameVariants=nv,
    )

    assert_eq(Dict.get(merged, "name"), Some("promptName"))
  })

  test("mergeAttributes: name variants seeded", () => {
    let cli = Dict.make()
    let prompts = Dict.make()
    let defaults = Dict.make()
    let nv = Context.makeNameVariants("MyComponent")

    let merged = Context.mergeAttributes(
      ~cliAttributes=cli,
      ~promptAnswers=prompts,
      ~manifestDefaults=defaults,
      ~nameVariants=nv,
    )

    assert_eq(Dict.get(merged, "Name"), Some("MyComponent"))
    assert_eq(Dict.get(merged, "name"), Some("my_component"))
  })

  test("build: creates complete context", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates/component",
      ~name="MyComponent",
      (),
    )

    assert_eq(ctx.cwd, "/workspace")
    assert_eq(ctx.actionfolder, "/workspace/_templates/component")
    assert_eq(ctx.nameVariants.pascalName, "MyComponent")
    assert_eq(ctx.nameVariants.name, "my_component")
  })

  test("toRenderContext: converts context correctly", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates/component",
      ~name="MyComponent",
      (),
    )

    let renderCtx = Context.toRenderContext(ctx)

    assert_eq(renderCtx.pascalName, "MyComponent")
    assert_eq(renderCtx.names, "my_components")
    assert_eq(renderCtx.cwd, "/workspace")
  })
})
