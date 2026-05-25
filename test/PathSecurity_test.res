// PathSecurity_test — unit tests for path traversal protection

open TestHelpers

let runTests = (label, pathAdapter) => {
  suite(`PathSecurity [${label}]`, () => {
    test("isWithinTree: path inside tree returns true", () => {
      let result = PathSecurity.isWithinTree("/home/user/project/src", "/home/user/project", pathAdapter)
      assert_true(result)
    })

    test("isWithinTree: path outside tree returns false", () => {
      let result = PathSecurity.isWithinTree("/home/user/other", "/home/user/project", pathAdapter)
      assert_false(result)
    })

    test("isWithinTree: path traversal attempt returns false", () => {
      let result = PathSecurity.isWithinTree("/home/user/project/../../../etc/passwd", "/home/user/project", pathAdapter)
      assert_false(result)
    })

    test("isWithinTree: absolute path inside returns true", () => {
      let result = PathSecurity.isWithinTree("/home/user/project", "/home/user/project", pathAdapter)
      assert_true(result)
    })

    test("isWithinTree: absolute path outside returns false", () => {
      let result = PathSecurity.isWithinTree("/etc/passwd", "/home/user/project", pathAdapter)
      assert_false(result)
    })

    test("isWithinTree: sibling path returns false", () => {
      let result = PathSecurity.isWithinTree("/home/user/project-sibling", "/home/user/project", pathAdapter)
      assert_false(result)
    })

    test("isWithinTree: deep nested path inside returns true", () => {
      let result = PathSecurity.isWithinTree("/home/user/project/src/components/Button/index.tsx", "/home/user/project", pathAdapter)
      assert_true(result)
    })

    test("isWithinTree: traversal to parent of root returns false", () => {
      let result = PathSecurity.isWithinTree("/home/user/../../../etc/passwd", "/home/user", pathAdapter)
      assert_false(result)
    })
  })
}

runTests("Node.js", NodeJsPath.make())
runTests("Deno", DenoPath.make())