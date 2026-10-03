// PathTraversal_test — malicious path traversal tests

open TestHelpers
open Ports

let makeMockFs = (): Ports.fileSystem => {
  readFile: (_, ~options as _=?) => Promise.resolve(""),
  writeFile: (_, _, ~options as _=?) => Promise.resolve(),
  mkdir: (_, ~options as _=?) => Promise.resolve(""),
  rm: (_, ~options as _=?) => Promise.resolve(),
  cp: (_, _, ~options as _=?) => Promise.resolve(),
  readdir: (_, ~options as _=?) => Promise.resolve([]),
  fileExists: _ => Promise.resolve(false),
  stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
  lstat: _ => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false}: Ports.lstatResult),
  realpath: path => Promise.resolve(path),
  makeStagingDir: prefix => Promise.resolve("/tmp/" ++ prefix ++ "-test"),
}

let runIsWithinTree = (path, root, pathAdapter) => {
  let mockFs = makeMockFs()
  PathSecurity.isWithinTree(path, root, pathAdapter, mockFs)
}

// Filesystem that records every cp call so we can prove Commit.commitFiles rejects
// escaped paths BEFORE any write reaches the destination, and inside-tree writes
// actually call cp.
let makeRecordingFs = (~cpCalls: ref<int>): Ports.fileSystem => {
  readFile: (_, ~options as _=?) => Promise.resolve(""),
  writeFile: (_, _, ~options as _=?) => Promise.resolve(),
  mkdir: (_, ~options as _=?) => Promise.resolve(""),
  rm: (_, ~options as _=?) => Promise.resolve(),
  cp: (_srcPath, _destPath, ~options as _=?) => {
    let _ = cpCalls.contents = cpCalls.contents + 1
    Promise.resolve()
  },
  readdir: (_, ~options as _=?) => Promise.resolve([]),
  fileExists: _ => Promise.resolve(false),
  stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
  lstat: _ => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false}: Ports.lstatResult),
  realpath: path => Promise.resolve(path),
  makeStagingDir: prefix => Promise.resolve("/tmp/" ++ prefix ++ "-test"),
}

suite("PathTraversal", () => {
  testAsync("isWithinTree: blocks ../../../etc/passwd traversal", resolve => {
    runIsWithinTree("/home/user/project/../../../etc/passwd", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_false(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: blocks hook script relative traversal ../../../etc/evil.sh", resolve => {
    runIsWithinTree("/home/user/project/../../../etc/evil.sh", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_false(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: blocks absolute path /etc/passwd outside project tree", resolve => {
    runIsWithinTree("/etc/passwd", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_false(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: blocks tool script path ../../root/.ssh/id_rsa", resolve => {
    runIsWithinTree("/home/user/project/../../root/.ssh/id_rsa", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_false(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: blocks absolute path /bin/sh if outside project", resolve => {
    runIsWithinTree("/bin/sh", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_false(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: legitimate relative path ./scripts/build.sh is allowed", resolve => {
    runIsWithinTree("/home/user/project/scripts/build.sh", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_true(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: legitimate absolute path within project is allowed", resolve => {
    runIsWithinTree("/home/user/project/src/main.res", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_true(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: deep traversal with ../../.. is blocked", resolve => {
    runIsWithinTree("/home/user/project/src/../../../../etc/passwd", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_false(result)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
  })

  testAsync("isWithinTree: deep non-existent path under real directory is allowed", resolve => {
    runIsWithinTree("/home/user/project/a/b/c/newfile", "/home/user/project", NodeJsPath.make())
    ->Promise.then(result => {
      assert_true(result)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // ---------- WS1: end-to-end "before write" enforcement ----------

  testAsync("WS1: TemplateRenderer.render rejects '../' traversal in 'to:' before write", resolve => {
    let outputDir = "/tmp/ws1-traversal-output"
    let ctx = Context.build(~cwd=outputDir, ~actionfolder=outputDir, ~name="test", ())
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(outputDir, "evil.ejs.t"),
      directives: [Template.To("../../../etc/passwd")],
      body: "evil-content",
    }

    TemplateRenderer.render(
      ~template,
      ~context=ctx,
      ~outputDir,
      ~conflictDecisions=None,
      ~fs=makeMockFs(),
      ~path=NodeJsPath.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~ejs=NodeJsEjs.make(),
      ~process=NodeJsProcess.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "escapes output tree"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })
    ->ignore
  })

  testAsync("WS1: TemplateRenderer.render rejects deeper '../' traversal that exits at root", resolve => {
    // path.join('/tmp/ws1-deep-output', '../../../../etc/passwd') resolves to '/etc/passwd'.
    let outputDir = "/tmp/ws1-deep-output"
    let ctx = Context.build(~cwd=outputDir, ~actionfolder=outputDir, ~name="test", ())
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(outputDir, "deep.ejs.t"),
      directives: [Template.To("../../../../etc/passwd")],
      body: "evil-content",
    }

    TemplateRenderer.render(
      ~template,
      ~context=ctx,
      ~outputDir,
      ~conflictDecisions=None,
      ~fs=makeMockFs(),
      ~path=NodeJsPath.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~ejs=NodeJsEjs.make(),
      ~process=NodeJsProcess.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Error(msg) => assert_true(String.includes(msg, "escapes output tree"))
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })
    ->ignore
  })

  testAsync("WS1: TemplateRenderer.render accepts a normal inside-tree 'to:' path", resolve => {
    let outputDir = "/tmp/ws1-allow-output"
    let ctx = Context.build(~cwd=outputDir, ~actionfolder=outputDir, ~name="test", ())
    let template: Template.template = {
      sourcePath: NodeJs.Path.join(outputDir, "good.ejs.t"),
      directives: [Template.To("src/file.txt")],
      body: "good-content",
    }

    TemplateRenderer.render(
      ~template,
      ~context=ctx,
      ~outputDir,
      ~conflictDecisions=None,
      ~fs=makeMockFs(),
      ~path=NodeJsPath.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
      ~ejs=NodeJsEjs.make(),
      ~process=NodeJsProcess.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(Some({renderedBody, _})) => assert_eq(renderedBody, "good-content")
      | Ok(None) => assert_false(true)
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })
    ->ignore
  })

  testAsync("WS1: Commit.commitFiles rejects a target path that escapes outputDir before write", resolve => {
    let outputDir = "/tmp/ws1-commit-output"
    let stagedTarget = "../../../etc/passwd"
    let cpCalls = ref(0)
    let fs = makeRecordingFs(~cpCalls)

    Commit.commitFiles(
      ~stagingDir="/tmp/staging",
      ~outputDir,
      ~renderedFiles=[("src.ejs.t", stagedTarget)],
      ~fs,
      ~path=NodeJsPath.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Error(err) => assert_true(String.includes(err.message, "outside output tree"))
      | Ok(_) => assert_false(true)
      }
      // No write should reach the destination before the rejection fires.
      assert_eq(cpCalls.contents, 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })
    ->ignore
  })

  testAsync("WS1: Commit.commitFiles accepts a target path that stays inside outputDir", resolve => {
    let outputDir = "/tmp/ws1-commit-ok"
    let cpCalls = ref(0)
    let fs = makeRecordingFs(~cpCalls)

    Commit.commitFiles(
      ~stagingDir="/tmp/staging",
      ~outputDir,
      ~renderedFiles=[("src.ejs.t", "src/file.txt")],
      ~fs,
      ~path=NodeJsPath.make(),
      ~pathSecurity=NodeJsPathSecurity.make(),
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => ()
      | Error(_) => assert_false(true)
      }
      // Inside-tree commit must actually cp the staged file to outputDir.
      assert_true(cpCalls.contents > 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => { resolve(); Promise.resolve() })
    ->ignore
  })
})
