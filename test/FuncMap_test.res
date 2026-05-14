// FuncMap_test — case conversion tests
// Tests all funcmap functions: pascalCase, camelCase, kebabCase, snakeCase, upper, lower, trim, title

suite("FuncMap", () => {
  test("pascalCase: snake_case", () => {
    assert_eq(FuncMap.pascalCase("hello_world"), "HelloWorld")
  })

  test("pascalCase: kebab-case", () => {
    assert_eq(FuncMap.pascalCase("hello-world"), "HelloWorld")
  })

  test("pascalCase: camelCase input", () => {
    assert_eq(FuncMap.pascalCase("helloWorld"), "HelloWorld")
  })

  test("pascalCase: consecutive uppercase", () => {
    assert_eq(FuncMap.pascalCase("helloAPIWorld"), "HelloApiWorld")
  })

  test("pascalCase: empty string", () => {
    assert_eq(FuncMap.pascalCase(""), "")
  })

  test("pascalCase: single char", () => {
    assert_eq(FuncMap.pascalCase("a"), "A")
  })

  test("camelCase: snake_case", () => {
    assert_eq(FuncMap.camelCase("hello_world"), "helloWorld")
  })

  test("camelCase: kebab-case", () => {
    assert_eq(FuncMap.camelCase("hello-world"), "helloWorld")
  })

  test("camelCase: pascalCase input", () => {
    assert_eq(FuncMap.camelCase("HelloWorld"), "helloWorld")
  })

  test("camelCase: empty string", () => {
    assert_eq(FuncMap.camelCase(""), "")
  })

  test("kebabCase: snake_case", () => {
    assert_eq(FuncMap.kebabCase("hello_world"), "hello-world")
  })

  test("kebabCase: PascalCase", () => {
    assert_eq(FuncMap.kebabCase("HelloWorld"), "hello-world")
  })

  test("kebabCase: empty string", () => {
    assert_eq(FuncMap.kebabCase(""), "")
  })

  test("snakeCase: PascalCase", () => {
    assert_eq(FuncMap.snakeCase("HelloWorld"), "hello_world")
  })

  test("snakeCase: kebab-case", () => {
    assert_eq(FuncMap.snakeCase("hello-world"), "hello_world")
  })

  test("snakeCase: empty string", () => {
    assert_eq(FuncMap.snakeCase(""), "")
  })

  test("upper: basic", () => {
    assert_eq(FuncMap.upper("hello"), "HELLO")
  })

  test("lower: basic", () => {
    assert_eq(FuncMap.lower("HELLO"), "hello")
  })

  test("trim: whitespace", () => {
    assert_eq(FuncMap.trim("  hello  "), "hello")
  })

  test("title: basic", () => {
    assert_eq(FuncMap.title("hello world"), "Hello World")
  })

  test("capitalize: basic", () => {
    assert_eq(FuncMap.capitalize("hello"), "Hello")
  })

  test("capitalize: empty", () => {
    assert_eq(FuncMap.capitalize(""), "")
  })

  test("uncapitalize: basic", () => {
    assert_eq(FuncMap.uncapitalize("Hello"), "hello")
  })

  test("makeHelpers: returns object with all functions", () => {
    let h = FuncMap.makeHelpers()
    assert_eq(h.pascalCase("hello_world"), "HelloWorld")
    assert_eq(h.camelCase("hello_world"), "helloWorld")
    assert_eq(h.kebabCase("HelloWorld"), "hello-world")
    assert_eq(h.snakeCase("HelloWorld"), "hello_world")
  })
})