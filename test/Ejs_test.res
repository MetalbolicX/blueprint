open TestHelpers

suite("Ejs", () => {
  test("render: produces expected output with valid template and dict", () => {
    let template = "Hello <%= name %>!"
    let data = Dict.make()
    Dict.set(data, "name", "world")
    let result = Bindings.Ejs.render(template, data)
    assert_eq(result, "Hello world!")
  })

  test("render: handles multiple variables", () => {
    let template = "<%= greeting %> <%= subject %>!"
    let data = Dict.make()
    Dict.set(data, "greeting", "Hello")
    Dict.set(data, "subject", "reScript")
    let result = Bindings.Ejs.render(template, data)
    assert_eq(result, "Hello reScript!")
  })

  test("render: with empty dict renders template as-is", () => {
    let template = "static content"
    let data = Dict.make()
    let result = Bindings.Ejs.render(template, data)
    assert_eq(result, "static content")
  })

  test("render: with options — custom delimiter", () => {
    let template = "Hello <?= name ?>!"
    let data = Dict.make()
    Dict.set(data, "name", "test")
    let opts: Bindings.Ejs.options = {delimiter: "?"}
    let result = Bindings.Ejs.render(template, data, ~options=opts)
    assert_eq(result, "Hello test!")
  })

  testAsync("renderFile: renders a file template (temp file)", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let templatePath = NodeJs.Path.join(tmpDir, "test.ejs")
    let templateContent = "Value: <%= val %>"
    NodeJs.Fs.writeFile(templatePath, templateContent)
    ->Promise.then(_ => {
      let data = Dict.make()
      Dict.set(data, "val", "42")
      Bindings.Ejs.renderFile(templatePath, data)
    })
    ->Promise.then(result => {
      assert_eq(result, "Value: 42")
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  test("render: escapes HTML by default", () => {
    let template = "<%= content %>"
    let data = Dict.make()
    Dict.set(data, "content", "<script>alert('xss')</script>")
    let result = Bindings.Ejs.render(template, data)
    assert_true(String.includes(result, "&lt;script&gt;"))
    assert_false(String.includes(result, "<script>"))
  })
})