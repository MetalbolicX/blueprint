// Phase2Integration_test — phase2 atomic commit and shell execution integration tests

open TestHelpers

let rejectError: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)

let makeDeps = () => {
  (
    NodeJsFileSystem.make(),
    NodeJsPath.make(),
    NodeJsProcess.make(),
    NodeJsShell.make(),
  )
}

let makeFsWithRestoreFailure = (~failingRestoreFromPath: string): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()

  {
    readFile: (file, ~options=?) => base.readFile(file, ~options?),
    writeFile: (file, content, ~options=?) => base.writeFile(file, content, ~options?),
    mkdir: (dir, ~options=?) => base.mkdir(dir, ~options?),
    rm: (target, ~options=?) => base.rm(target, ~options?),
    cp: (fromPath, toPath, ~options=?) =>
      if fromPath == failingRestoreFromPath {
        rejectError("restore failed for " ++ toPath)
      } else {
        base.cp(fromPath, toPath, ~options?)
      },
    readdir: (dir, ~options=?) => base.readdir(dir, ~options?),
    fileExists: file => base.fileExists(file),
    stat: file => base.stat(file),
    lstat: file => base.lstat(file),
    realpath: file => base.realpath(file),
    makeStagingDir: prefix => base.makeStagingDir(prefix),
  }
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
          // For missing staging dir, partialCommit should be None (nothing was committed)
          assert_true(e.partialCommit == None)
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

  testAsync("run: returns Error when tool execution fails after file commit", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let renderedFiles = [("t.ejs.t", "out.txt")]

    let shellConfig: Config.shellConfig = {
      enabled: true,
      tools: [{name: "failing-tool", command: "node", args: ["-e", "process.exit(7)"]}],
    }

    let toolDef: Config.shellTool = {
      name: "failing-tool",
      command: "node",
      args: ["-e", "process.exit(7)"],
    }

    let shellCommands: array<Template.shellCommand> = [
      {target: Template.ToolCall({name: "failing-tool", toolDef, sourcePath: "t.ejs.t"}), sourcePath: "t.ejs.t"},
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
      | Ok(_) => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Error(err) => {
          assert_true(String.includes(err.message, "Tool 'failing-tool' exited with code"))
          NodeJs.Fs.fileExists(NodeJs.Path.join(outputDir, "out.txt"))
          ->Promise.then(exists => {
            assert_false(exists)
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns catastrophic error when shell failure and output rollback restore both fail", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let path = NodeJsPath.make()
    let processAdapter = NodeJsProcess.make()
    let shell = NodeJsShell.make()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let outputFile = NodeJs.Path.join(outputDir, "out.txt")
    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let backupPath = NodeJs.Path.join(stagingDir, ".blueprint-backup/out.txt")
    let fs = makeFsWithRestoreFailure(~failingRestoreFromPath=backupPath)
    let renderedFiles = [("t.ejs.t", "out.txt")]

    let shellConfig: Config.shellConfig = {
      enabled: true,
      tools: [{name: "failing-tool", command: "node", args: ["-e", "process.exit(7)"]}],
    }

    let toolDef: Config.shellTool = {
      name: "failing-tool",
      command: "node",
      args: ["-e", "process.exit(7)"],
    }

    let shellCommands: array<Template.shellCommand> = [
      {target: Template.ToolCall({name: "failing-tool", toolDef, sourcePath: "t.ejs.t"}), sourcePath: "t.ejs.t"},
    ]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "new content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputFile, "original content"))
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
      | Ok(_) => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Error(err) => {
          assert_true(String.includes(err.message, "Tool 'failing-tool' exited with code"))
          assert_true(err.catastrophic == Some(true))
          switch err.failedRollbackFiles {
          | Some(paths) => {
              assert_eq(Array.length(paths), 1)
              assert_eq(Array.get(paths, 0), Some(outputFile))
            }
          | None => assert_false(true)
          }

          NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"})
          ->Promise.then(content => {
            assert_eq(content, "new content")
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns Error when fetch validation fails after file commit", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let renderedFiles = [("t.ejs.t", "out.txt")]
    let shellCommands: array<Template.shellCommand> = [
      {target: Template.Fetch("ftp://example.com/archive.tar.gz"), sourcePath: "t.ejs.t"},
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
      | Ok(_) => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Error(err) => {
          assert_true(String.includes(err.message, "Fetch failed"))
          NodeJs.Fs.fileExists(NodeJs.Path.join(outputDir, "out.txt"))
          ->Promise.then(exists => {
            assert_false(exists)
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: returns Error when script fails after file commit", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedFile = NodeJs.Path.join(stagingDir, "out.txt")
    let stagedScript = NodeJs.Path.join(stagingDir, "scripts/post.sh")
    let outputScript = NodeJs.Path.join(outputDir, "scripts/post.sh")
    let renderedFiles = [("t.ejs.t", "out.txt"), ("scripts/post.sh.ejs.t", "scripts/post.sh")]
    let shellCommands: array<Template.shellCommand> = [
      {target: Template.ScriptFile(outputScript), sourcePath: "scripts/post.sh.ejs.t"},
    ]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedFile), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedScript), ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedScript, "#!/bin/sh\nexit 9\n"))
    ->Promise.then(_ => NodeJs.ChildProcess.execShellCommand(~command="chmod +x \"" ++ stagedScript ++ "\""))
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
      | Ok(_) => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Error(err) => {
          assert_true(String.includes(err.message, "Script exited with code 9"))
          NodeJs.Fs.fileExists(NodeJs.Path.join(outputDir, "out.txt"))
          ->Promise.then(exists => {
            assert_false(exists)
            NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
            resolve()
            Promise.resolve()
          })
        }
      }
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
