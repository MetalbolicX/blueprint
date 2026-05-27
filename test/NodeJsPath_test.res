open TestHelpers

suite("NodeJsPath adapter", () => {
  let p = NodeJsPath.make()

  test("join combines two paths", () => {
    assert_eq(p.join("a", "b"), "a/b")
    assert_eq(p.join("/a", "b"), "/a/b")
    assert_eq(p.join("a", "/b"), "a/b")
  })

  test("resolve creates absolute path", () => {
    let resolved = p.resolve("/a", "b")
    assert_true(p.isAbsolute(resolved))
  })

  test("dirname extracts directory portion", () => {
    assert_eq(p.dirname("a/b/c.txt"), "a/b")
    assert_eq(p.dirname("a.txt"), ".")
    assert_eq(p.dirname("/a/b"), "/a")
  })

  test("basename extracts filename", () => {
    assert_eq(p.basename("a/b/c.txt"), "c.txt")
    assert_eq(p.basename("a/b/c.txt", ~ext=".txt"), "c")
    assert_eq(p.basename("a/b/c.txt", ~ext=".md"), "c.txt")
  })

  test("isAbsolute identifies absolute paths", () => {
    assert_eq(p.isAbsolute("/"), true)
    assert_eq(p.isAbsolute("/a/b"), true)
    assert_eq(p.isAbsolute("a/b"), false)
    assert_eq(p.isAbsolute("./a"), false)
  })
})
