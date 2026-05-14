// ConflictResolver_test — y/n/s/a resolution tests

suite("ConflictResolver", () => {
  test("resolution: variants", () => {
    let r1 = ConflictResolver.YesAll
    let r2 = ConflictResolver.NoAll
    let r3 = ConflictResolver.Select
    let r4 = ConflictResolver.Abort

    assert_true(true)  // Just verify variants exist
  })

  test("parseChoice: y/yes/all", () => {
    assert_eq(ConflictResolver.parseChoice("y"), Some(ConflictResolver.YesAll))
    assert_eq(ConflictResolver.parseChoice("yes"), Some(ConflictResolver.YesAll))
    assert_eq(ConflictResolver.parseChoice("all"), Some(ConflictResolver.YesAll))
  })

  test("parseChoice: n/no", () => {
    assert_eq(ConflictResolver.parseChoice("n"), Some(ConflictResolver.NoAll))
    assert_eq(ConflictResolver.parseChoice("no"), Some(ConflictResolver.NoAll))
  })

  test("parseChoice: s/select", () => {
    assert_eq(ConflictResolver.parseChoice("s"), Some(ConflictResolver.Select))
    assert_eq(ConflictResolver.parseChoice("select"), Some(ConflictResolver.Select))
  })

  test("parseChoice: abort", () => {
    assert_eq(ConflictResolver.parseChoice("abort"), Some(ConflictResolver.Abort))
  })

  test("parseChoice: invalid input", () => {
    assert_eq(ConflictResolver.parseChoice("maybe"), None)
  })

  test("fileConflict: structure", () => {
    let fc = {
      ConflictResolver.sourcePath: "/templates/Hello.tsx.ejs.t",
      targetPath: "/output/Hello.tsx",
    }

    assert_eq(fc.sourcePath, "/templates/Hello.tsx.ejs.t")
    assert_eq(fc.targetPath, "/output/Hello.tsx")
  })

  test("conflictDecision: structure", () => {
    let cd = {
      ConflictResolver.sourcePath: "/templates/Hello.tsx.ejs.t",
      targetPath: "/output/Hello.tsx",
      overwrite: true,
    }

    assert_true(cd.overwrite)
  })

  test("resolveConflicts: empty conflicts list", () => {
    let rl = Bindings.Readline.createInterface(
      ~input=Node.Process.stdin,
      ~output=Node.Process.stdout,
      (),
    )

    let result = ConflictResolver.resolveConflicts(
      ~rl,
      ~conflicts=[],
      ~force=false,
    )

    switch result {
    | Ok(decisions) => assert_eq(Js.Array.length(decisions), 0)
    | Error(_) => assert_false(true)
    }
  })
})