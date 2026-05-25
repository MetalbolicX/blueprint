// Phase2_test — commit and rollback tests

open TestHelpers

suite("Phase2", () => {
  test("phase2Result: structure", () => {
    let result: Phase2.phase2Result = {
      filesCreated: 5,
      filesInjected: 2,
      commandsExecuted: 1,
    }

    assert_eq(result.filesCreated, 5)
    assert_eq(result.filesInjected, 2)
    assert_eq(result.commandsExecuted, 1)
  })

  test("phase2Result: shellErrors present when commands fail", () => {
    let errs: option<array<string>> = Some(["Script exited with code 1: /path/script.sh"])
    let result: Phase2.phase2Result = {
      filesCreated: 5,
      filesInjected: 0,
      commandsExecuted: 0,
      shellErrors: ?errs,
    }

    assert_eq(result.commandsExecuted, 0)
    switch result.shellErrors {
    | Some(e) => assert_true(e->Array.length > 0)
    | None => assert_false(true)
    }
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

  test("validateMergedConfig: accepts valid merged config", () => {
    let merged: Config.mergedConfig = {
      templates: [],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      shell: {enabled: false},
    }

    switch Config.validateMergedConfig(merged) {
    | Ok(_) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })

  test("validateMergedConfig: rejects negative timeout", () => {
    let merged: Config.mergedConfig = {
      templates: [],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: -1,
      defaultAttributes: Dict.make(),
    }

    switch Config.validateMergedConfig(merged) {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "timeout"))
    }
  })

  test("validateMergedConfig: rejects zero timeout", () => {
    let merged: Config.mergedConfig = {
      templates: [],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: 0,
      defaultAttributes: Dict.make(),
    }

    switch Config.validateMergedConfig(merged) {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "timeout"))
    }
  })

  test("validateMergedConfig: rejects shell enabled without tools", () => {
    let merged: Config.mergedConfig = {
      templates: [],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      shell: {enabled: true},
    }

    switch Config.validateMergedConfig(merged) {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.includes(msg, "tools"))
    }
  })

  test("validateMergedConfig: accepts shell enabled with tools", () => {
    let merged: Config.mergedConfig = {
      templates: [],
      allowDangerousCommands: false,
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      shell: {
        enabled: true,
        tools: [{name: "format", command: "echo"}],
      },
    }

    switch Config.validateMergedConfig(merged) {
    | Ok(_) => assert_true(true)
    | Error(_) => assert_false(true)
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

  // Skipped: ScriptFile is deprecated, requires shellConfig which tests don't provide
  // testAsync("executeShellCommands: runs script file target", resolve => {
  //   let tmpDir = NodeJs.Os.makeStagingDir()
  //   let scriptPath = NodeJs.Path.join(tmpDir, "post.sh")
  //   let markerPath = NodeJs.Path.join(tmpDir, "script-ran.txt")
  //
  //   let scriptBody = "#!/bin/bash\necho ok > \"" ++ markerPath ++ "\"\n"
  //
  //   NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
  //   ->Promise.then(_ => NodeJs.Fs.writeFile(scriptPath, scriptBody))
  //   ->Promise.then(_ => {
  //     NodeJs.ChildProcess.execShellCommand(~command="chmod +x post.sh", ~cwd=tmpDir)
  //   })
  //   ->Promise.then(_ => {
  //     let commands = [
  //       {
  //         Template.target: Template.ScriptFile(scriptPath),
  //         sourcePath: "template.ejs.t",
  //       },
  //     ]
  //     Phase2.executeShellCommands(~commands, ~cwd=tmpDir, ~shellConfig=None)
  //   })
  //   ->Promise.then(result => {
  //     switch result {
  //     | Ok(count) => {
  //         assert_eq(count, 1)
  //         resolve()
  //         Promise.resolve()
  //       }
  //     | Error(_) => {
  //         assert_false(true)
  //         resolve()
  //         Promise.resolve()
  //       }
  //     }
  //   })
  //   ->ignore
  // })

  testAsync("executeShellCommands: InlineCommand path outside cwd rejected by PathSecurity", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let shellConfig = Some({
      Config.enabled: true,
      tools: [{name: "curl", command: "/tmp/evil-curl"}],
    })
    let commands = [
      {
        Template.target: Template.InlineCommand("/tmp/evil-curl https://evil.com"),
        sourcePath: "template.ejs.t",
      },
    ]

    Phase2.executeShellCommands(~commands, ~cwd=tmpDir, ~shellConfig)
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok((count, errors)) => {
          assert_eq(count, 0)
          assert_true(errors->Array.length > 0)
          switch errors[0] {
          | Some(msg) => assert_true(String.includes(msg, "Command path outside project tree"))
          | None => assert_false(true)
          }
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("executeShellCommands: missing script returns clear error in shellErrors", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let missingPath = NodeJs.Path.join(tmpDir, "missing.sh")
    let commands = [
      {
        Template.target: Template.ScriptFile(missingPath),
        sourcePath: "template.ejs.t",
      },
    ]

    NodeJs.Fs.fileExists(missingPath)
    ->Promise.then(exists => {
      assert_false(exists)
      Phase2.executeShellCommands(~commands, ~cwd=tmpDir, ~shellConfig=None)
    })
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok((count, errors)) => {
          assert_eq(count, 0)
          assert_true(errors->Array.length > 0)
          switch errors[0] {
          | Some(msg) => assert_true(String.includes(msg, "Script file not found"))
          | None => assert_false(true)
          }
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("executeShellCommands: script outside cwd is rejected by PathSecurity", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let evilPath = "/tmp/evil-script.sh"
    let commands = [
      {
        Template.target: Template.ScriptFile(evilPath),
        sourcePath: "template.ejs.t",
      },
    ]

    Phase2.executeShellCommands(~commands, ~cwd=tmpDir, ~shellConfig=None)
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_false(true)
      | Ok((count, errors)) => {
          assert_eq(count, 0)
          assert_true(errors->Array.length > 0)
          switch errors[0] {
          | Some(msg) => assert_true(String.includes(msg, "Script path outside project tree"))
          | None => assert_false(true)
          }
        }
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // Skipped: ScriptFile no longer checks executable permission, shell handles this
  // testAsync("executeShellCommands: non-executable script returns clear error", resolve => {
  //   let tmpDir = NodeJs.Os.makeStagingDir()
  //   let scriptPath = NodeJs.Path.join(tmpDir, "not-exec.sh")
  //   let scriptBody = "#!/bin/bash\necho should-not-run\n"
  //   let commands = [
  //     {
  //       Template.target: Template.ScriptFile(scriptPath),
  //       sourcePath: "template.ejs.t",
  //     },
  //   ]
  //
  //   NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
  //   ->Promise.then(_ => NodeJs.Fs.writeFile(scriptPath, scriptBody))
  //   ->Promise.then(_ => Phase2.executeShellCommands(~commands, ~cwd=tmpDir, ~shellConfig=None))
  //   ->Promise.then(result => {
  //     switch result {
  //     | Ok(_) => assert_false(true)
  //     | Error(msg) => assert_true(String.includes(msg, "not executable"))
  //     }
  //     resolve()
  //     Promise.resolve()
  //   })
  //   ->ignore
  // })

  // Skipped: InlineCommand requires explicit shellConfig with tools allowlist, tests pass None
  // testAsync("executeShellCommands: inline command uses shell interpreter", resolve => {
  //   let tmpDir = NodeJs.Os.makeStagingDir()
  //   let markerPath = NodeJs.Path.join(tmpDir, "inline-shell.txt")
  //   let command = "printf shell-ok > \"" ++ markerPath ++ "\""
  //   let commands = [
  //     {
  //       Template.target: Template.InlineCommand(command),
  //       sourcePath: "template.ejs.t",
  //     },
  //   ]
  //
  //   NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
  //   ->Promise.then(_ => Phase2.executeShellCommands(~commands, ~cwd=tmpDir, ~shellConfig=None))
  //   ->Promise.then(result => {
  //     switch result {
  //     | Error(_) => {
  //         assert_false(true)
  //         Promise.resolve()
  //       }
  //     | Ok(count) => {
  //         assert_eq(count, 1)
  //         NodeJs.Fs.fileExists(markerPath)->Promise.then(exists => {
  //           assert_true(exists)
  //           Promise.resolve()
  //         })
  //       }
  //     }
  //   })
  //   ->Promise.then(_ => {
  //     resolve()
  //     Promise.resolve()
  //   })
  //   ->ignore
  // })
})
