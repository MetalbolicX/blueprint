// Phase0_test — prompt resolution tests

suite("Phase0", () => {
  test("phase0Result: structure", () => {
    let result = {
      Phases.Phase0.resolvedAttributes: Js.Dict.empty(),
      conflicts: [],
    }

    assert_true(Js.Dict.length(result.resolvedAttributes) == 0)
    assert_eq(Js.Array.length(result.conflicts), 0)
  })

  test("conflictFile: structure", () => {
    let cf = {
      Phases.Phase0.sourcePath: "/templates/Hello.tsx.ejs.t",
      targetPath: "/output/Hello.tsx",
    }

    assert_eq(cf.sourcePath, "/templates/Hello.tsx.ejs.t")
    assert_eq(cf.targetPath, "/output/Hello.tsx")
  })
})