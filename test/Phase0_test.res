// Phase0_test — prompt resolution tests

open TestHelpers

suite("Phase0", () => {
  test("phase0Result: structure", () => {
    let result = {
      Phase0.resolvedAttributes: Js.Dict.empty(),
      conflicts: [],
    }

    assert_true(Dict.toArray(result.resolvedAttributes)->Array.length == 0)
    assert_eq(Js.Array.length(result.conflicts), 0)
  })

  test("conflictFile: structure", () => {
    let cf = {
      Phase0.sourcePath: "/templates/Hello.tsx.ejs.t",
      targetPath: "/output/Hello.tsx",
    }

    assert_eq(cf.sourcePath, "/templates/Hello.tsx.ejs.t")
    assert_eq(cf.targetPath, "/output/Hello.tsx")
  })
})