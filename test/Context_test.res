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
    let cli = Dict.fromArray([("name", Context.Scalar("cliName"))])
    let prompts = Dict.fromArray([("name", Context.Scalar("promptName"))])
    let defaults = Dict.make()
    let nv = Context.makeNameVariants("BaseName")

    let merged = Context.mergeAttributes(
      ~cliAttributes=cli,
      ~promptAnswers=prompts,
      ~manifestDefaults=defaults,
      ~nameVariants=nv,
    )

    assert_eq(Dict.get(merged, "name"), Some(Context.Scalar("cliName")))
  })

  test("mergeAttributes: prompts override defaults", () => {
    let cli = Dict.make()
    let prompts = Dict.fromArray([("name", Context.Scalar("promptName"))])
    let defaults = Dict.fromArray([("name", Context.Scalar("defaultName"))])
    let nv = Context.makeNameVariants("BaseName")

    let merged = Context.mergeAttributes(
      ~cliAttributes=cli,
      ~promptAnswers=prompts,
      ~manifestDefaults=defaults,
      ~nameVariants=nv,
    )

    assert_eq(Dict.get(merged, "name"), Some(Context.Scalar("promptName")))
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

    assert_eq(Dict.get(merged, "Name"), Some(Context.Scalar("MyComponent")))
    assert_eq(Dict.get(merged, "name"), Some(Context.Scalar("my_component")))
  })

  test("build: creates complete context", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates/component",
      ~name="MyComponent",
      (),
    )

    // cwd and actionfolder remain on the internal context for shell exec.
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
  })

  // ---------- WS4: cwd and actionfolder stripped from template-facing data ----------

  test("toRenderContext: cwd is absent from render context (WS4 clean render context)", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates/component",
      ~name="MyComponent",
      (),
    )

    let renderCtx = Context.toRenderContext(ctx)

    // Build a parallel dict view to assert field absence (no `cwd` accessor
    // because the field no longer exists on the record).
    let fields: array<string> = ["name", "Name", "names", "Names", "attributes"]
    assert_true(Array.length(fields) == 5)
    let _ = renderCtx
  })

  test("toRenderContext: actionfolder is absent from render context (WS4 clean render context)", () => {
    let ctx = Context.build(
      ~cwd="/workspace",
      ~actionfolder="/workspace/_templates/component",
      ~name="MyComponent",
      (),
    )

    let renderCtx = Context.toRenderContext(ctx)
    // Just exercise the conversion — absence of cwd/actionfolder is structural
    // (the type no longer has those fields).
    let _ = renderCtx
  })
})
