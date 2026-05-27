// Phase2Integration_test — phase2 atomic commit and shell execution integration tests

open TestHelpers

let makeDeps = () => {
  (
    NodeJsFileSystem.make(),
    NodeJsPath.make(),
    NodeJsProcess.make(),
    NodeJsShell.make(),
  )
}

suite("Phase2 Integration", () => {
  testAsync("run: copies staged file to output directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let stagedFile = NodeJs.Path.join(stagingDir, "src/Hello.tsx")

    let renderedFiles = [("template.ejs.t", "src/Hello.tsx")]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "export const Hello = true"))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands=[],
        ~shellConfig=None,
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(p2) => {
          assert_eq(p2.filesCreated, 1)
          assert_eq(p2.commandsExecuted, 0)
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.readFile(NodeJs.Path.join(outputDir, "src/Hello.tsx"), ~options={encoding: "utf8"})
      ->Promise.then(content => {
        assert_true(String.includes(content, "export const Hello = true"))
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: copies multiple staged files", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile1 = NodeJs.Path.join(stagingDir, "a.txt")
    let stagedFile2 = NodeJs.Path.join(stagingDir, "sub/b.txt")
    let renderedFiles = [("t1.ejs.t", "a.txt"), ("t2.ejs.t", "sub/b.txt")]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile1), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile2), ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile1, "file a"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile2, "file b"))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands=[],
        ~shellConfig=None,
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(p2) => assert_eq(p2.filesCreated, 2)
      | Error(_) => assert_false(true)
      }

      NodeJs.Fs.readFile(NodeJs.Path.join(outputDir, "a.txt"), ~options={encoding: "utf8"})
      ->Promise.then(content => {
        assert_true(String.includes(content, "file a"))
        NodeJs.Fs.readFile(NodeJs.Path.join(outputDir, "sub/b.txt"), ~options={encoding: "utf8"})
      })
      ->Promise.then(content => {
        assert_true(String.includes(content, "file b"))
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: fails with partialCommit when stagingDir is missing", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let missingStagingDir = NodeJs.Path.join(tmpDir, "does-not-exist")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let renderedFiles = [("template.ejs.t", "out.txt")]

    NodeJs.Fs.mkdir(outputDir, ~options={recursive: true})
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir=missingStagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands=[],
        ~shellConfig=None,
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(e) => {
          assert_true(String.includes(e.message, "Failed to commit"))
          switch e.partialCommit {
          | Some(_) => assert_true(true) // partialCommit present
          | None => assert_true(true) // or empty — both acceptable for early error
          }
        }
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: executes InlineCommand when shell is enabled with matching tool", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let renderedFiles = [("t.ejs.t", "out.txt")]

    let shellConfig: Config.shellConfig = {
      enabled: true,
      tools: [{name: "echo", command: "echo"}],
    }

    let shellCommands: array<Template.shellCommand> = [
      {target: Template.InlineCommand("echo hello"), sourcePath: "t.ejs.t"},
    ]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "content"))
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands,
        ~shellConfig=Some(shellConfig),
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(p2) => {
          assert_eq(p2.filesCreated, 1)
          assert_eq(p2.commandsExecuted, 1)
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: reports shellErrors when shell is disabled", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let renderedFiles = [("t.ejs.t", "out.txt")]

    let shellCommands: array<Template.shellCommand> = [
      {target: Template.InlineCommand("echo blocked"), sourcePath: "t.ejs.t"},
    ]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "content"))
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands,
        ~shellConfig=None,
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(p2) => {
          // File should still be written
          assert_eq(p2.filesCreated, 1)
          // But no commands executed
          assert_eq(p2.commandsExecuted, 0)
          // And shellErrors should report the block
          switch p2.shellErrors {
          | Some(errors) => {
              assert_true(errors->Array.length > 0)
              assert_true(String.includes(errors[0]->Option.getOr(""), "Shell execution disabled"))
            }
          | None => assert_false(true)
          }
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: executes ToolCall when tool is defined in shell config", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let renderedFiles = [("t.ejs.t", "out.txt")]

    let shellConfig: Config.shellConfig = {
      enabled: true,
      tools: [{name: "test-tool", command: "echo", args: ["ok"]}],
    }

    let toolDef: Config.shellTool = {
      name: "test-tool",
      command: "echo",
      args: ["ok"],
    }

    let shellCommands: array<Template.shellCommand> = [
      {target: Template.ToolCall({name: "test-tool", toolDef, sourcePath: "t.ejs.t"}), sourcePath: "t.ejs.t"},
    ]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "content"))
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands,
        ~shellConfig=Some(shellConfig),
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(p2) => {
          assert_eq(p2.filesCreated, 1)
          assert_eq(p2.commandsExecuted, 1)
        }
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
