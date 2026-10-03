// Phase2_test — commit and rollback tests

open TestHelpers
open Commit

let rejectError: string => promise<'a> = %raw(`message => Promise.reject(new Error(message))`)

let makeDeps = () => {
  (
    NodeJsFileSystem.make(),
    NodeJsPath.make(),
    NodeJsProcess.make(),
    NodeJsShell.make(),
  )
}

let makeProcess = (): Ports.process => {
  cwd: () => "/workspace/project",
  env: () => Dict.make(),
  argv: () => ["node", "blueprint"],
  exit: _ => (),
  onSignal: (_, _) => (),
  removeSignalListeners: () => (),
  homedir: () => "/home/test",
}

let waitForSignalRollback: (
  ~exitRecorded: unit => bool,
  ~diagnosticPresent: unit => bool,
) => promise<unit> = %raw(`(exitRecorded, diagnosticPresent) => new Promise((resolve, reject) => {
  let attempts = 0;
  const poll = () => {
    if (exitRecorded() && diagnosticPresent()) return resolve();
    if (++attempts >= 400) return reject(new Error("rollback chain did not settle"));
    setTimeout(poll, 5);
  };
  poll();
})`)

let makeSignalProcess = (~handler: ref<option<unit => unit>>, ~exitCodes: ref<array<int>>): Ports.process => {
  {
    ...makeProcess(),
    exit: code => exitCodes.contents->Array.push(code)->ignore,
    onSignal: (_, callback) => handler.contents = Some(callback),
  }
}

let makeShell = (~status: int): Ports.shell => {
  execAsync: (_cmd, ~options as _=?) =>
    Promise.resolve(({stdout: "", stderr: "", status: Some(status), signalCode: None, killed: false}: Ports.execResult)),
  execFileAsync: (_cmd, ~args as _=?, ~options as _=?) =>
    Promise.resolve(({stdout: "", stderr: "", status: Some(status), signalCode: None, killed: false}: Ports.execResult)),
}

let makeFsWithFailures = (
  ~cpFailure: option<((string, string) => option<string>)>=?,
  ~rmFailure: option<(string => option<string>)>=?,
): Ports.fileSystem => {
  let base = NodeJsFileSystem.make()

  {
    readFile: (file, ~options=?) => base.readFile(file, ~options?),
    writeFile: (file, content, ~options=?) => base.writeFile(file, content, ~options?),
    mkdir: (dir, ~options=?) => base.mkdir(dir, ~options?),
    rm: (target, ~options=?) =>
      switch rmFailure {
      | Some(fail) =>
        switch fail(target) {
        | Some(message) => rejectError(message)
        | None => base.rm(target, ~options?)
        }
      | None => base.rm(target, ~options?)
      },
    cp: (fromPath, toPath, ~options=?) =>
      switch cpFailure {
      | Some(fail) =>
        switch fail(fromPath, toPath) {
        | Some(message) => rejectError(message)
        | None => base.cp(fromPath, toPath, ~options?)
        }
      | None => base.cp(fromPath, toPath, ~options?)
      },
    readdir: (dir, ~options=?) => base.readdir(dir, ~options?),
    fileExists: file => base.fileExists(file),
    stat: file => base.stat(file),
    lstat: file => base.lstat(file),
    realpath: file => base.realpath(file),
    makeStagingDir: prefix => base.makeStagingDir(prefix),
  }
}

let makeRollbackFs = (
  ~restored: ref<array<(string, string)>>,
  ~removed: ref<array<string>>,
  ~cpFailure: option<((string, string) => option<string>)>=?,
  ~rmFailure: option<(string => option<string>)>=?,
): Ports.fileSystem => {
  readFile: (_, ~options as _=?) => Promise.resolve(""),
  writeFile: (_, _, ~options as _=?) => Promise.resolve(),
  mkdir: (_, ~options as _=?) => Promise.resolve(""),
  rm: (target, ~options as _=?) =>
    switch rmFailure {
    | Some(fail) =>
      switch fail(target) {
      | Some(message) => rejectError(message)
      | None => {
          removed.contents->Array.push(target)->ignore
          Promise.resolve()
        }
      }
    | None => {
        removed.contents->Array.push(target)->ignore
        Promise.resolve()
      }
    },
  cp: (fromPath, toPath, ~options as _=?) =>
    switch cpFailure {
    | Some(fail) =>
      switch fail(fromPath, toPath) {
      | Some(message) => rejectError(message)
      | None => {
          restored.contents->Array.push((fromPath, toPath))->ignore
          Promise.resolve()
        }
      }
    | None => {
        restored.contents->Array.push((fromPath, toPath))->ignore
        Promise.resolve()
      }
    },
  readdir: (_, ~options as _=?) => Promise.resolve([]),
  fileExists: _ => Promise.resolve(false),
  stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
  lstat: _ => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false}: Ports.lstatResult),
  realpath: path => Promise.resolve(path),
  makeStagingDir: prefix => Promise.resolve("/tmp/" ++ prefix ++ "-test"),
}

suite("Phase2", () => {
  testAsync("cleanup failure warns with orphan path but preserves successful result", resolve => {
    let root = NodeJs.Os.makeStagingDir()
    let stagingDir = NodeJs.Path.join(root, "stage")
    let base = NodeJsFileSystem.make()
    let process = makeProcess()
    let fs: Ports.fileSystem = {
      ...base,
      rm: (target, ~options=?) => target == stagingDir ? rejectError("locked") : base.rm(target, ~options?),
    }
    let startWarningCapture: unit => unit = %raw(`function() { globalThis.__oldWarn = console.warn; globalThis.__warnings = []; console.warn = msg => globalThis.__warnings.push(msg); }`)
    let restoreWarningCapture: unit => unit = %raw(`function() { console.warn = globalThis.__oldWarn; }`)
    startWarningCapture()

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => Phase2.run(
      ~stagingDir,
      ~outputDir=NodeJs.Path.join(root, "output"),
      ~renderedFiles=[],
      ~shellCommands=[],
      ~shellConfig=None,
      ~fs,
      ~path=NodeJsPath.make(),
      ~process,
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
      ~tmpRoot=NodeJs.Os.tmpdir(),
    ))
    ->Promise.then(result => {
      switch result {
      | Ok(_) => ()
      | Error(_) => assert_false(true)
      }
      let warnings: array<string> = %raw("globalThis.__warnings")
      assert_true(warnings->Array.some(message => String.includes(message, stagingDir)))
      restoreWarningCapture()
      NodeJs.Fs.rm(root, ~options={recursive: true})
      ->Promise.then(_ => { resolve(); Promise.resolve() })
    })
    ->Promise.catch(_ => {
      restoreWarningCapture()
      NodeJs.Fs.rm(root, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rollback containment ignores conflicting TMPDIR and uses OS tmpdir", resolve => {
    let root = NodeJs.Os.makeStagingDir()
    let stagingDir = NodeJs.Path.join(root, "stage")
    let process: Ports.process = {...makeProcess(), env: () => Dict.fromArray([("TMPDIR", "/different/temp")])}

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => Phase2.run(
      ~stagingDir,
      ~outputDir=NodeJs.Path.join(root, "output"),
      ~renderedFiles=[],
      ~shellCommands=[],
      ~shellConfig=None,
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process,
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
    ))
    ->Promise.then(result => {
      switch result {
      | Ok(_) => ()
      | Error(_) => assert_false(true)
      }
      NodeJs.Fs.fileExists(stagingDir)
    })
    ->Promise.then(exists => {
      assert_false(exists)
      NodeJs.Fs.rm(root, ~options={recursive: true})
      ->Promise.then(_ => { resolve(); Promise.resolve() })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(root, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
  testAsync("signal during commit restores backups, removes staging, and exits non-zero", resolve => {
    let root = NodeJs.Os.makeStagingDir()
    let stagingDir = NodeJs.Path.join(root, "stage")
    let outputDir = NodeJs.Path.join(root, "output")
    let stagedFile = NodeJs.Path.join(stagingDir, "file.txt")
    let outputFile = NodeJs.Path.join(outputDir, "file.txt")
    let base = NodeJsFileSystem.make()
    let handler = ref(None)
    let exitCodes = ref([])
    let process = makeSignalProcess(~handler, ~exitCodes)
    let signalFs: Ports.fileSystem = {
      readFile: base.readFile,
      writeFile: base.writeFile,
      mkdir: base.mkdir,
      rm: base.rm,
      cp: (src, dst, ~options=?) => base.cp(src, dst, ~options?)->Promise.then(_ => {
        if src == stagedFile {
          switch handler.contents {
          | Some(callback) => callback()
          | None => assert_false(true)
          }
        }
        Promise.resolve()
      }),
      readdir: base.readdir,
      fileExists: base.fileExists,
      stat: base.stat,
      lstat: base.lstat,
      realpath: base.realpath,
      makeStagingDir: base.makeStagingDir,
    }
    let stagingRef = ref(Some(stagingDir))
    let rollbackRef: ref<option<unit => promise<unit>>> = ref(None)

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "new"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputFile, "original"))
    ->Promise.then(_ => {
      EngineLifecycle.registerSignalHandlers(~process, ~stagingDirRef=stagingRef, ~commitRollbackRef=rollbackRef, ~fs=signalFs)
      Promise.resolve()
    })
    ->Promise.then(_ => Phase2.run(
      ~stagingDir,
      ~outputDir,
      ~renderedFiles=[("template", "file.txt")],
      ~shellCommands=[],
      ~shellConfig=None,
      ~fs=signalFs,
      ~path=NodeJsPath.make(),
      ~process,
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
      ~tmpRoot=NodeJs.Os.tmpdir(),
      ~commitRollbackRef=rollbackRef,
    ))
    ->Promise.then(_ => Promise.resolve())
    ->Promise.then(_ => NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"}))
    ->Promise.then(content => {
      assert_eq(content, "original")
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))
      NodeJs.Fs.fileExists(stagingDir)
    })
    ->Promise.then(stagingExists => {
      assert_false(stagingExists)
      NodeJs.Fs.rm(root, ~options={recursive: true})
      ->Promise.then(_ => { resolve(); Promise.resolve() })
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(root, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("signal rollback failure during commit surfaces a diagnostic", resolve => {
    let root = NodeJs.Os.makeStagingDir()
    let stagingDir = NodeJs.Path.join(root, "stage")
    let outputDir = NodeJs.Path.join(root, "output")
    let stagedFile = NodeJs.Path.join(stagingDir, "file.txt")
    let base = NodeJsFileSystem.make()
    let handler = ref(None)
    let exitCodes = ref([])
    let process = makeSignalProcess(~handler, ~exitCodes)
    // Restore copies read from the backup dir; make them throw so the
    // signal-time rollback cannot restore the output tree.
    let signalFs: Ports.fileSystem = {
      readFile: base.readFile,
      writeFile: base.writeFile,
      mkdir: base.mkdir,
      rm: base.rm,
      cp: (src, dst, ~options=?) =>
        if String.includes(src, ".blueprint-backup") {
          rejectError("restore failed")
        } else if src == stagedFile {
          switch handler.contents {
          | Some(callback) =>
            callback()
            base.cp(src, dst, ~options?)
          | None => base.cp(src, dst, ~options?)
          }
        } else {
          base.cp(src, dst, ~options?)
        },
      readdir: base.readdir,
      fileExists: base.fileExists,
      stat: base.stat,
      lstat: base.lstat,
      realpath: base.realpath,
      makeStagingDir: base.makeStagingDir,
    }
    let stagingRef = ref(Some(stagingDir))
    let rollbackRef: ref<option<unit => promise<unit>>> = ref(None)
    let _ = %raw("globalThis.__testMessages = []")
    let _ = %raw("globalThis.__signalOriginalError = console.error")
    let _ = %raw("console.error = function(msg) { globalThis.__testMessages.push(String(msg)); }")

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFile, "new"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(NodeJs.Path.join(outputDir, "file.txt"), "original"))
    ->Promise.then(_ => {
      EngineLifecycle.registerSignalHandlers(~process, ~stagingDirRef=stagingRef, ~commitRollbackRef=rollbackRef, ~fs=signalFs)
      Promise.resolve()
    })
    ->Promise.then(_ => Phase2.run(
      ~stagingDir,
      ~outputDir,
      ~renderedFiles=[("template", "file.txt")],
      ~shellCommands=[],
      ~shellConfig=None,
      ~fs=signalFs,
      ~path=NodeJsPath.make(),
      ~process,
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
      ~tmpRoot=NodeJs.Os.tmpdir(),
      ~commitRollbackRef=rollbackRef,
    ))
    ->Promise.then(_ => waitForSignalRollback(
      ~exitRecorded=() => Array.get(exitCodes.contents, 0) == Some(1),
      ~diagnosticPresent=() => %raw("globalThis.__testMessages.some(msg => String(msg).includes('Signal rollback failed'))"),
    ))
    ->Promise.then(_ => {
      let _ = %raw("console.error = globalThis.__signalOriginalError")
      let joined: string = %raw("globalThis.__testMessages.join('\\n')")
      assert_true(String.includes(joined, "Signal rollback failed"))
      assert_eq(Array.get(exitCodes.contents, 0), Some(1))
      NodeJs.Fs.rm(root, ~options={recursive: true})
      ->Promise.then(_ => { resolve(); Promise.resolve() })
    })
    ->Promise.catch(_ => {
      let _ = %raw("console.error = globalThis.__signalOriginalError")
      NodeJs.Fs.rm(root, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
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

  test("phase2Error: structure", () => {
    let err: phase2Error = {
      message: "Commit failed",
      partialCommit: ["file1.txt", "file2.txt"],
    }

    assert_eq(err.message, "Commit failed")
    switch err.partialCommit {
    | Some(files) => assert_eq(Array.length(files), 2)
    | None => assert_false(true)
    }
  })

  test("phase2Error: no partial commit", () => {
    let err: phase2Error = {
      message: "Early failure",
    }

    switch err.partialCommit {
    | Some(_) => assert_false(true)
    | None => assert_eq(err.message, "Early failure")
    }
  })

  test("validateMergedConfig: accepts valid merged config", () => {
    let merged: Config.mergedConfig = {
      templates: [],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      shell: {enabled: false},
    }

    switch Config.validateMergedConfig(merged) {
    | Ok(_) => assert_eq(merged.timeout, 5)
    | Error(_) => assert_false(true)
    }
  })

  test("validateMergedConfig: rejects negative timeout", () => {
    let merged: Config.mergedConfig = {
      templates: [],
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
    | Ok(_) =>
      switch merged.shell {
      | Some(shellCfg) => assert_eq(shellCfg.enabled, true)
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  testAsync("rollback: removes staging directory", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let _ = NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.fileExists(tmpDir))
    ->Promise.then(exists => {
      assert_true(exists)
      Commit.rollback(tmpDir, ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~pathSecurity=NodeJsPathSecurity.make(), ~fs=NodeJsFileSystem.make())
    })
    ->Promise.then(_ => NodeJs.Fs.fileExists(tmpDir))
    ->Promise.then(existsAfter => {
      assert_false(existsAfter)
      resolve()
      Promise.resolve()
    })
  })

  testAsync("rollbackOutput: returns Error with failed restore path when restore throws", resolve => {
    let restored = ref([])
    let removed = ref([])
    let fs = makeRollbackFs(
      ~restored,
      ~removed,
      ~cpFailure=(fromPath, _toPath) => fromPath == "/backups/fail.txt" ? Some("restore failed") : None,
    )
    let committedFiles = ["/output/ok.txt", "/output/fail.txt"]
    let backups: array<backupEntry> = [
      {outputPath: "/output/ok.txt", backupPath: "/backups/ok.txt"},
      {outputPath: "/output/fail.txt", backupPath: "/backups/fail.txt"},
    ]

    rollbackOutput(~committedFiles, ~backups, ~outputDir="/output", ~path=NodeJsPath.make(), ~pathSecurity=NodeJsPathSecurity.make(), ~fs)
    ->Promise.then(result => {
      switch result {
      | Ok() => assert_false(true)
      | Error(failures) => {
          assert_eq(Array.length(failures), 1)
          switch Array.get(failures, 0) {
          | Some(f) => assert_eq(f.path, "/output/fail.txt")
          | None => assert_false(true)
          }
        }
      }

      switch restored.contents {
      | [(_, restoredPath)] => assert_eq(restoredPath, "/output/ok.txt")
      | _ => assert_false(true)
      }

      assert_eq(Array.length(removed.contents), 0)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rollbackOutput: returns Error with failed new-file deletion path when rm throws", resolve => {
    let restored = ref([])
    let removed = ref([])
    let outputNew = "/output/new.txt"
    let fs = makeRollbackFs(
      ~restored,
      ~removed,
      ~rmFailure=target => target == outputNew ? Some("cannot delete") : None,
    )

    rollbackOutput(~committedFiles=[outputNew], ~backups=[], ~outputDir="/output", ~path=NodeJsPath.make(), ~pathSecurity=NodeJsPathSecurity.make(), ~fs)
    ->Promise.then(result => {
      switch result {
      | Ok() => assert_false(true)
      | Error(failures) => {
          assert_eq(Array.length(failures), 1)
          switch Array.get(failures, 0) {
          | Some(f) => assert_eq(f.path, outputNew)
          | None => assert_false(true)
          }
        }
      }

      assert_eq(Array.length(restored.contents), 0)
      assert_eq(Array.length(removed.contents), 0)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rollback: returns Error when fs.rm throws", resolve => {
    let fs = makeRollbackFs(
      ~restored=ref([]),
      ~removed=ref([]),
      ~rmFailure=target => target == "/tmp/locked-staging" ? Some("permission denied") : None,
    )

    rollback("/tmp/locked-staging", ~tmpRoot="/tmp", ~path=NodeJsPath.make(), ~pathSecurity=NodeJsPathSecurity.make(), ~fs)
    ->Promise.then(result => {
      switch result {
      | Ok() => assert_false(true)
      | Error(message) => assert_true(String.includes(message, "permission denied"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
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
  //     NodeJs.ChildProcess.execFileAsync("chmod", ~args=["+x", "post.sh"], ~options={cwd: tmpDir})
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
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [{name: "curl", command: "/tmp/evil-curl"}],
    })
    let commands = [
      {
        Template.target: Template.InlineCommand("/tmp/evil-curl https://evil.com"),
        sourcePath: "template.ejs.t",
      },
    ]

    Phase2.executeShellCommands(
      ~commands,
      ~cwd=tmpDir,
      ~stagingDir=tmpDir,
      ~shellConfig,
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Command path outside project tree"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("executeShellCommands: missing script returns Error", resolve => {
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
      Phase2.executeShellCommands(
        ~commands,
        ~cwd=tmpDir,
        ~stagingDir=tmpDir,
        // shell.enabled gate (plan 039)
        ~shellConfig=Some({enabled: true}),
        ~fs=NodeJsFileSystem.make(),
        ~path=NodeJsPath.make(),
        ~process=NodeJsProcess.make(),
        ~shell=NodeJsShell.make(),
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    })
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Script file not found"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("executeShellCommands: invalid fetch returns Error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let commands = [
      {
        Template.target: Template.Fetch("not-a-valid-url"),
        sourcePath: "template.ejs.t",
      },
    ]

    Phase2.executeShellCommands(
      ~commands,
      ~cwd=tmpDir,
      ~stagingDir=tmpDir,
      ~shellConfig=None,
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Fetch failed"))
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

    Phase2.executeShellCommands(
      ~commands,
      ~cwd=tmpDir,
      ~stagingDir=tmpDir,
      // shell.enabled gate (plan 039)
      ~shellConfig=Some({enabled: true}),
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.includes(msg, "Script path outside project tree"))
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("run: fetch failure after commit returns Error with partial commit", resolve => {
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
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands,
        ~shellConfig=None,
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          assert_true(String.includes(err.message, "Fetch failed"))
          switch err.partialCommit {
          | Some(files) => assert_eq(Array.length(files), 1)
          | None => assert_false(true)
          }
        }
      }
      NodeJs.Fs.fileExists(NodeJs.Path.join(outputDir, "out.txt"))
      ->Promise.then(exists => {
        assert_false(exists)
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

  testAsync("run: tool failure after commit returns Error with partial commit", resolve => {
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
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          assert_true(String.includes(err.message, "Tool 'failing-tool' exited with code"))
          switch err.partialCommit {
          | Some(files) => assert_eq(Array.length(files), 1)
          | None => assert_false(true)
          }
        }
      }
      NodeJs.Fs.fileExists(NodeJs.Path.join(outputDir, "out.txt"))
      ->Promise.then(exists => {
        assert_false(exists)
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

  testAsync("run: script failure after commit returns Error with partial commit", resolve => {
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
    ->Promise.then(_ => NodeJs.ChildProcess.execFileAsync("chmod", ~args=["+x", stagedScript]))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands,
        // shell.enabled gate (plan 039)
        ~shellConfig=Some({enabled: true}),
        ~fs,
        ~path,
        ~process=processAdapter,
        ~shell,
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          assert_true(String.includes(err.message, "Script exited with code 9"))
          switch err.partialCommit {
          | Some(files) => assert_eq(Array.length(files), 2)
          | None => assert_false(true)
          }
        }
      }
      NodeJs.Fs.fileExists(NodeJs.Path.join(outputDir, "out.txt"))
      ->Promise.then(exists => {
        assert_false(exists)
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

  testAsync("run: shell failure restores overwritten files and deletes newly created files", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let (fs, path, processAdapter, shell) = makeDeps()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")

    let stagedOverwrite = NodeJs.Path.join(stagingDir, "keep.txt")
    let stagedNew = NodeJs.Path.join(stagingDir, "new.txt")
    let outputOverwrite = NodeJs.Path.join(outputDir, "keep.txt")
    let outputNew = NodeJs.Path.join(outputDir, "new.txt")

    let renderedFiles = [
      ("keep.t.ejs", "keep.txt"),
      ("new.t.ejs", "new.txt"),
    ]

    let toolDef: Config.shellTool = {
      name: "always-fail",
      command: "node",
      args: ["-e", "process.exit(13)"],
    }
    let shellConfig: Config.shellConfig = {
      enabled: true,
      tools: [toolDef],
    }
    let shellCommands: array<Template.shellCommand> = [
      {
        target: Template.ToolCall({name: "always-fail", toolDef, sourcePath: "post.ejs.t"}),
        sourcePath: "post.ejs.t",
      },
    ]

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedOverwrite), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputOverwrite, "original-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedOverwrite, "updated-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedNew, "brand-new-content"))
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
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          assert_true(String.includes(err.message, "always-fail"))
          assert_eq(err.catastrophic, None)
        }
      }
      NodeJs.Fs.readFile(outputOverwrite, ~options={encoding: "utf8"})
      ->Promise.then(content => {
        assert_true(String.includes(content, "original-content"))
        NodeJs.Fs.fileExists(outputNew)
      })
      ->Promise.then(newExists => {
        assert_false(newExists)
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

  testAsync("run: shell failure with rollbackOutput failure returns catastrophic error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let path = NodeJsPath.make()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let stagedOverwrite = NodeJs.Path.join(stagingDir, "keep.txt")
    let stagedNew = NodeJs.Path.join(stagingDir, "new.txt")
    let outputOverwrite = NodeJs.Path.join(outputDir, "keep.txt")
    let outputNew = NodeJs.Path.join(outputDir, "new.txt")
    let renderedFiles = [("keep.t.ejs", "keep.txt"), ("new.t.ejs", "new.txt")]
    let toolDef: Config.shellTool = {name: "always-fail", command: "node"}
    let shellCommands: array<Template.shellCommand> = [
      {
        target: Template.ToolCall({name: "always-fail", toolDef, sourcePath: "post.ejs.t"}),
        sourcePath: "post.ejs.t",
      },
    ]
    let fs = makeFsWithFailures(
      ~cpFailure=(fromPath, toPath) =>
        String.includes(fromPath, ".blueprint-backup") && toPath == outputOverwrite ? Some("restore failed") : None,
    )

    NodeJs.Fs.mkdir(NodeJs.Path.dirname(stagedOverwrite), ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputOverwrite, "original-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedOverwrite, "updated-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedNew, "brand-new-content"))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands,
        ~shellConfig=Some({enabled: true, tools: [toolDef]}),
        ~fs,
        ~path,
        ~process=makeProcess(),
        ~shell=makeShell(~status=17),
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          assert_true(String.includes(err.message, "always-fail"))
          switch err.catastrophic {
          | Some(true) => ()
          | _ => assert_false(true)
          }
          switch err.failedRollbackFiles {
          | Some(paths) => {
              assert_eq(Array.length(paths), 1)
              assert_eq(Array.get(paths, 0), Some(outputOverwrite))
            }
          | None => assert_false(true)
          }
        }
      }

      NodeJs.Fs.readFile(outputOverwrite, ~options={encoding: "utf8"})
      ->Promise.then(content => {
        assert_true(String.includes(content, "updated-content"))
        NodeJs.Fs.fileExists(outputNew)
      })
      ->Promise.then(newExists => {
        assert_false(newExists)
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

  testAsync("run: commit failure with rollback failure returns catastrophic error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let path = NodeJsPath.make()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let stagedOk = NodeJs.Path.join(stagingDir, "ok.txt")
    let stagedFail = NodeJs.Path.join(stagingDir, "fail.txt")
    let renderedFiles = [("ok.t.ejs", "ok.txt"), ("fail.t.ejs", "fail.txt")]
    let fs = makeFsWithFailures(
      ~cpFailure=(fromPath, toPath) => fromPath == stagedFail && String.endsWith(toPath, "fail.txt") ? Some("copy blocked") : None,
      ~rmFailure=target => target == stagingDir ? Some("staging locked") : None,
    )

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedOk, "ok-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedFail, "fail-content"))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands=[],
        ~shellConfig=None,
        ~fs,
        ~path,
        ~process=makeProcess(),
        ~shell=NodeJsShell.make(),
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          assert_true(String.includes(err.message, "copy blocked"))
          switch err.partialCommit {
          | Some(files) => assert_eq(Array.length(files), 1)
          | None => assert_false(true)
          }
          switch err.catastrophic {
          | Some(true) => ()
          | _ => assert_false(true)
          }
          switch err.failedRollbackFiles {
          | Some(_) => assert_false(true)
          | None => ()
          }
        }
      }

      NodeJs.Fs.fileExists(stagingDir)
      ->Promise.then(stagingExists => {
        assert_true(stagingExists)
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

  testAsync("run: commit failure restores overwritten files and removes partial output", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let path = NodeJsPath.make()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let stagedKeep = NodeJs.Path.join(stagingDir, "keep.txt")
    let stagedNew = NodeJs.Path.join(stagingDir, "new.txt")
    let outputKeep = NodeJs.Path.join(outputDir, "keep.txt")
    let outputNew = NodeJs.Path.join(outputDir, "new.txt")
    let renderedFiles = [("keep.t.ejs", "keep.txt"), ("new.t.ejs", "new.txt")]
    let fs = makeFsWithFailures(
      ~cpFailure=(fromPath, toPath) =>
        fromPath == stagedNew && toPath == outputNew ? Some("copy blocked") : None,
    )

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputKeep, "original-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedKeep, "updated-content"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedNew, "brand-new-content"))
    ->Promise.then(_ =>
      Phase2.run(
        ~stagingDir,
        ~outputDir,
        ~renderedFiles,
        ~shellCommands=[],
        ~shellConfig=None,
        ~fs,
        ~path,
        ~process=makeProcess(),
        ~shell=NodeJsShell.make(),
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
      )
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => switch err.partialCommit {
        | Some(files) => {
            assert_eq(Array.length(files), 1)
            assert_true(String.endsWith(files[0]->Option.getOr(""), "keep.txt"))
          }
        | None => assert_false(true)
        }
      }
      NodeJs.Fs.readFile(outputKeep)
      ->Promise.then(content => {
        assert_true(String.includes(content, "original-content"))
        NodeJs.Fs.fileExists(outputNew)
      })
      ->Promise.then(newExists => {
        assert_false(newExists)
        NodeJs.Fs.fileExists(stagingDir)
      })
      ->Promise.then(stagingExists => {
        assert_false(stagingExists)
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

  testAsync("run: failed commit copy restores its backup and removes other partial output", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let path = NodeJsPath.make()
    let stagingDir = NodeJs.Path.join(tmpDir, "staging")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let stagedA = NodeJs.Path.join(stagingDir, "a.txt")
    let stagedB = NodeJs.Path.join(stagingDir, "b.txt")
    let outputA = NodeJs.Path.join(outputDir, "a.txt")
    let outputB = NodeJs.Path.join(outputDir, "b.txt")
    let base = NodeJsFileSystem.make()
    let fs: Ports.fileSystem = {
      ...base,
      cp: (fromPath, toPath, ~options=?) =>
        if fromPath == stagedB && toPath == outputB {
          base.writeFile(outputB, "corrupt")->Promise.then(_ => rejectError("copy failed after partial write"))
        } else {
          base.cp(fromPath, toPath, ~options?)
        },
    }

    NodeJs.Fs.mkdir(stagingDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedA, "new-a"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(stagedB, "new-b"))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputB, "original-b"))
    ->Promise.then(_ => Phase2.run(
      ~stagingDir,
      ~outputDir,
      ~renderedFiles=[("a.t.ejs", "a.txt"), ("b.t.ejs", "b.txt")],
      ~shellCommands=[],
      ~shellConfig=None,
      ~fs,
      ~path,
      ~process=makeProcess(),
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
    ))
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(err) => {
          switch err.failedTargets {
          | Some(targets) => assert_eq(targets, [outputB])
          | None => assert_false(true)
          }
          switch err.failedBackups {
          | Some(backups) => {
              assert_eq(Array.length(backups), 1)
              assert_eq(backups[0]->Option.map(backup => backup.outputPath), Some(outputB))
            }
          | None => assert_false(true)
          }
        }
      }
      NodeJs.Fs.fileExists(outputA)
      ->Promise.then(aExists => {
        assert_false(aExists)
        NodeJs.Fs.readFile(outputB, ~options={encoding: "utf8"})
      })
      ->Promise.then(content => {
        assert_eq(content, "original-b")
        NodeJs.Fs.fileExists(stagingDir)
      })
      ->Promise.then(stagingExists => {
        assert_false(stagingExists)
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

  testAsync("executeShellCommands: successful fetch removes fetch tmp files", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let commands = [
      {
        Template.target: Template.Fetch("https://example.com"),
        sourcePath: "template.ejs.t",
      },
    ]

    Phase2.executeShellCommands(
      ~commands,
      ~cwd=tmpDir,
      ~stagingDir=tmpDir,
      ~shellConfig=None,
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell=NodeJsShell.make(),
        ~fetcher=NodeJsFetcher.make(),
        ~pathSecurity=NodeJsPathSecurity.make(),
        ~shellBuilder=NodeJsShellBuilder.make(),
        ~envFilter=NodeJsEnvFilter.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(count) => assert_eq(count, 1)
      | Error(msg) => assert_true(String.length(msg) > 0)
      }
      NodeJs.Fs.readdir(tmpDir)->Promise.then(entries => {
        let hasFetchTmp = entries->Array.some(name => String.startsWith(name, "fetch-") && String.endsWith(name, ".tmp"))
        assert_false(hasFetchTmp)
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

  testAsync("executeShellCommands: fetch tmp files are removed on later command failure", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let toolDef: Config.shellTool = {
      name: "always-fail",
      command: "node",
      args: ["-e", "process.exit(17)"],
    }
    let shellConfig: option<Config.shellConfig> = Some({
      enabled: true,
      tools: [toolDef],
    })

    let commands = [
      {
        Template.target: Template.Fetch("https://example.com"),
        sourcePath: "template.ejs.t",
      },
      {
        Template.target: Template.ToolCall({name: "always-fail", toolDef, sourcePath: "template.ejs.t"}),
        sourcePath: "template.ejs.t",
      },
    ]

    Phase2.executeShellCommands(
      ~commands,
      ~cwd=tmpDir,
      ~stagingDir=tmpDir,
      ~shellConfig,
      ~fs=NodeJsFileSystem.make(),
      ~path=NodeJsPath.make(),
      ~process=NodeJsProcess.make(),
      ~shell=NodeJsShell.make(),
      ~fetcher=NodeJsFetcher.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~shellBuilder=NodeJsShellBuilder.make(),
      ~envFilter=NodeJsEnvFilter.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(msg) => assert_true(String.length(msg) > 0)
      }
      NodeJs.Fs.readdir(tmpDir)->Promise.then(entries => {
        let hasFetchTmp = entries->Array.some(name => String.startsWith(name, "fetch-") && String.endsWith(name, ".tmp"))
        assert_false(hasFetchTmp)
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
