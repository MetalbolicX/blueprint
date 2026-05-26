// ConflictResolver_test — y/n/s/a resolution tests

open TestHelpers

suite("ConflictResolver", () => {
  test("resolution: variants", () => {
    let _r1 = ConflictResolver.YesAll
    let _r2 = ConflictResolver.NoAll
    let _r3 = ConflictResolver.Select
    let _r4 = ConflictResolver.Abort

    assert_true(true) // Just verify variants exist
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

testAsync("resolveConflicts: empty conflicts list", resolve => {
  let _rl = Bindings.NodeJs.Readline.createInterface(
    ~input=Bindings.NodeJs.Readline.stdin,
    ~output=Bindings.NodeJs.Readline.stdout,
    (),
  )

    let mockIo: Ports.interactiveIO = {
  ask: _ => Promise.resolve(""),
  askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
  close: () => ()
}

let _ = ConflictResolver.resolveConflicts(~io=mockIo, ~conflicts=[], ~force=false)->Promise.then(
      result => {
        switch result {
        | Ok(decisions) => assert_eq(Array.length(decisions), 0)
        | Error(_) => assert_false(true)
        }
        resolve()
        Promise.resolve()
      },
    )
  })

  testAsync("resolveConflicts: invalid input retries until valid", resolve => {
    let callCount = ref(0)
    let mockIo: Ports.interactiveIO = {
      ask: _ => {
        callCount.contents = callCount.contents + 1
        if callCount.contents == 1 {
          Promise.resolve("invalid")
        } else {
          Promise.resolve("yes")
        }
      },
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }

    let conflicts = [
      {
        ConflictResolver.sourcePath: "src",
        targetPath: "tgt"
      }
    ]

    ConflictResolver.resolveConflicts(~io=mockIo, ~conflicts, ~force=false)
    ->Promise.then(result => {
      switch result {
      | Ok(decisions) => {
          assert_eq(Array.length(decisions), 1)
          assert_eq(callCount.contents, 2)
          let overwrite = switch decisions[0] {
          | Some(d) => d.overwrite
          | None => false
          }
          assert_true(overwrite)
        }
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
