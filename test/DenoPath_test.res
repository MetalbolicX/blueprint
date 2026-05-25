open TestHelpers

suite("DenoPath adapter", () => {
  test("implements basic path operations", () => {
    let p = DenoPath.make()
    
    // basic ops
    assert_eq(p.join("a", "b"), "a/b")
    assert_eq(p.dirname("a/b/c.txt"), "a/b")
    assert_eq(p.basename("a/b/c.txt"), "c.txt")
    assert_eq(p.basename("a/b/c.txt", ~ext=".txt"), "c")
    
    assert_eq(p.isAbsolute("/a/b"), true)
    assert_eq(p.isAbsolute("a/b"), false)
  })
})
