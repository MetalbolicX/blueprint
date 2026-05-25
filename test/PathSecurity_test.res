// PathSecurity_test — unit tests for path traversal protection

open TestHelpers

suite("PathSecurity", () => {
  test("isWithinTree: path inside tree returns true", () => {
    let result = PathSecurity.isWithinTree("/home/user/project/src", "/home/user/project", NodeJsPath.make())
    assert_true(result)
  })

  test("isWithinTree: path outside tree returns false", () => {
    let result = PathSecurity.isWithinTree("/home/user/other", "/home/user/project", NodeJsPath.make())
    assert_false(result)
  })

  test("isWithinTree: path traversal attempt returns false", () => {
    let result = PathSecurity.isWithinTree("/home/user/project/../../../etc/passwd", "/home/user/project", NodeJsPath.make())
    assert_false(result)
  })

  test("isWithinTree: absolute path inside returns true", () => {
    let result = PathSecurity.isWithinTree("/home/user/project", "/home/user/project", NodeJsPath.make())
    assert_true(result)
  })

  test("isWithinTree: absolute path outside returns false", () => {
    let result = PathSecurity.isWithinTree("/etc/passwd", "/home/user/project", NodeJsPath.make())
    assert_false(result)
  })

  test("isWithinTree: sibling path returns false", () => {
    let result = PathSecurity.isWithinTree("/home/user/project-sibling", "/home/user/project", NodeJsPath.make())
    assert_false(result)
  })

  test("isWithinTree: deep nested path inside returns true", () => {
    let result = PathSecurity.isWithinTree("/home/user/project/src/components/Button/index.tsx", "/home/user/project", NodeJsPath.make())
    assert_true(result)
  })

  test("isWithinTree: traversal to parent of root returns false", () => {
    let result = PathSecurity.isWithinTree("/home/user/../../../etc/passwd", "/home/user", NodeJsPath.make())
    assert_false(result)
  })
})