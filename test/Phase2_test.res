// Phase2_test — commit and rollback tests

open TestHelpers

suite("Phase2", () => {
  test("phase2Result: structure", () => {
    let result = {
      Phase2.filesCreated: 5,
      filesInjected: 2,
      commandsExecuted: 1,
    }

    assert_eq(result.filesCreated, 5)
    assert_eq(result.filesInjected, 2)
    assert_eq(result.commandsExecuted, 1)
  })

  test("phase2Error: structure", () => {
    let err = {
      Phase2.message: "Commit failed",
      partialCommit: ["file1.txt", "file2.txt"],
    }

    assert_eq(err.message, "Commit failed")
    switch err.partialCommit {
    | Some(files) => assert_eq(Array.length(files), 2)
    | None => assert_false(true)
    }
  })

  test("phase2Error: no partial commit", () => {
    let err = {
      Phase2.message: "Early failure",
    }

    switch err.partialCommit {
    | Some(_) => assert_false(true)
    | None => assert_true(true)
    }
  })

  testAsync("rollback: removes staging directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let _ = NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.fileExists(tmpDir))
    ->Promise.then(exists => {
      assert_true(exists)
      Phase2.rollback(tmpDir)
    })
    ->Promise.then(_ => NodeJs.Fs.fileExists(tmpDir))
    ->Promise.then(existsAfter => {
      assert_false(existsAfter)
      resolve()
      Promise.resolve()
    })
  })
})
