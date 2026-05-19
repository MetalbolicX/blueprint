// PathTraversal_test — malicious path traversal tests

open TestHelpers

suite("PathTraversal", () => {
  test("isWithinTree: blocks ../../../etc/passwd traversal", () => {
    // Path traversal from project root to /etc/passwd
    let result = PathSecurity.isWithinTree(
      "/home/user/project/../../../etc/passwd",
      "/home/user/project",
    )
    assert_false(result)
  })

  test("isWithinTree: blocks hook script relative traversal ../../../etc/evil.sh", () => {
    // Simulating: command: "../../../etc/evil.sh" from /home/user/project
    let result = PathSecurity.isWithinTree(
      "/home/user/project/../../../etc/evil.sh",
      "/home/user/project",
    )
    assert_false(result)
  })

  test("isWithinTree: blocks absolute path /etc/passwd outside project tree", () => {
    // Absolute path to system file outside project
    let result = PathSecurity.isWithinTree("/etc/passwd", "/home/user/project")
    assert_false(result)
  })

  test("isWithinTree: blocks tool script path ../../root/.ssh/id_rsa", () => {
    // Malicious tool trying to access SSH keys
    let result = PathSecurity.isWithinTree(
      "/home/user/project/../../root/.ssh/id_rsa",
      "/home/user/project",
    )
    assert_false(result)
  })

  test("isWithinTree: blocks absolute path /bin/sh if outside project", () => {
    // Tool trying to execute system binary outside project tree
    let result = PathSecurity.isWithinTree("/bin/sh", "/home/user/project")
    assert_false(result)
  })

  test("isWithinTree: legitimate relative path ./scripts/build.sh is allowed", () => {
    // Legitimate script within project tree
    let result = PathSecurity.isWithinTree(
      "/home/user/project/scripts/build.sh",
      "/home/user/project",
    )
    assert_true(result)
  })

  test("isWithinTree: legitimate absolute path within project is allowed", () => {
    // Absolute path that is within project tree
    let result = PathSecurity.isWithinTree(
      "/home/user/project/src/main.res",
      "/home/user/project",
    )
    assert_true(result)
  })

  test("isWithinTree: deep traversal with ../../.. is blocked", () => {
    // Multiple parent directory traversal
    let result = PathSecurity.isWithinTree(
      "/home/user/project/src/../../../../etc/passwd",
      "/home/user/project",
    )
    assert_false(result)
  })
})