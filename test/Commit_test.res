// Commit_test — unit tests for Commit module rollback containment

open TestHelpers
open Commit

// Step 3: rollbackOutput must re-check containment before rm/cp
let testRollbackOutputDeniesOutOfTree = () => {
  testAsync("rollbackOutput: rejects out-of-tree committedFiles and does not rm", resolve => {
    let rmCalls: ref<array<string>> = ref([])
    let cpCalls: ref<array<string>> = ref([])

    let baseFs = NodeJsFileSystem.make()

    // Override rm/cp to track calls; return Ok so the function doesn't throw
    let mockFs: Ports.fileSystem = {
      readFile: baseFs.readFile,
      writeFile: baseFs.writeFile,
      mkdir: baseFs.mkdir,
      rm: (target, ~options as _=?) => {
        rmCalls.contents->Array.push(target)->ignore
        Promise.resolve()
      },
      cp: (src, dst, ~options as _=?) => {
        cpCalls.contents->Array.push(src ++ "=>" ++ dst)->ignore
        Promise.resolve()
      },
      readdir: baseFs.readdir,
      fileExists: _ => Promise.resolve(false),
      stat: _path => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
      realpath: path => Promise.resolve(path),
      makeStagingDir: baseFs.makeStagingDir,
    }

    // /etc/evil is clearly outside outputDir /home/user/project
    // Step 3: new signature with outputDir and path for containment check
    Commit.rollbackOutput(
      ~committedFiles=["/etc/evil"],
      ~backups=[],
      ~outputDir="/home/user/project",
      ~path=NodeJsPath.make(),
      ~fs=mockFs,
    )
    ->Promise.then(result => {
      // Must return Error (path is outside output tree)
      switch result {
      | Error(_) => assert_true(true)
      | Ok(_) => assert_true(false) // should NOT succeed
      }
      // rm must NEVER have been called on /etc/evil
      assert_true(rmCalls.contents->Array.length == 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      assert_true(rmCalls.contents->Array.length == 0)
      resolve()
      Promise.resolve()
    })->ignore
  })
}

// Step 3b: rollbackOutput allows in-tree paths (normal case)
let testRollbackOutputAllowsInTree = () => {
  testAsync("rollbackOutput: allows in-tree committedFiles and calls rm", resolve => {
    let rmCalls: ref<array<string>> = ref([])

    let baseFs = NodeJsFileSystem.make()

    let mockFs: Ports.fileSystem = {
      readFile: baseFs.readFile,
      writeFile: baseFs.writeFile,
      mkdir: baseFs.mkdir,
      rm: (target, ~options as _=?) => {
        rmCalls.contents->Array.push(target)->ignore
        Promise.resolve()
      },
      cp: (src, dst, ~options as _=?) => Promise.resolve(),
      readdir: baseFs.readdir,
      fileExists: _ => Promise.resolve(false),
      stat: _path => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
      realpath: path => Promise.resolve(path),
      makeStagingDir: baseFs.makeStagingDir,
    }

    // /home/user/project/src/index.ts is inside outputDir (new signature)
    Commit.rollbackOutput(
      ~committedFiles=["/home/user/project/src/index.ts"],
      ~backups=[],
      ~outputDir="/home/user/project",
      ~path=NodeJsPath.make(),
      ~fs=mockFs,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_true(true)
      | Error(_) => assert_true(false)
      }
      // rm SHOULD have been called (no backup for this file)
      assert_true(rmCalls.contents->Array.length > 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      assert_true(false)
      resolve()
      Promise.resolve()
    })->ignore
  })
}

// Step 4: rollback must assert staging dir is within tmpdir before recursive rm
let testRollbackDeniesNonTmpdir = () => {
  testAsync("rollback: refuses to rm path outside tmpdir", resolve => {
    let rmCalls: ref<array<string>> = ref([])
    let baseFs = NodeJsFileSystem.make()

    let mockFs: Ports.fileSystem = {
      readFile: baseFs.readFile,
      writeFile: baseFs.writeFile,
      mkdir: baseFs.mkdir,
      rm: (target, ~options as _=?) => {
        rmCalls.contents->Array.push(target)->ignore
        Promise.resolve()
      },
      cp: baseFs.cp,
      readdir: baseFs.readdir,
      fileExists: _ => Promise.resolve(false),
      stat: _path => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
      realpath: path => Promise.resolve(path),
      makeStagingDir: baseFs.makeStagingDir,
    }

    // /usr is not within /tmp — must be rejected
    Commit.rollback(
      "/usr",
      ~tmpRoot="/tmp",
      ~path=NodeJsPath.make(),
      ~fs=mockFs,
    )
    ->Promise.then(result => {
      switch result {
      | Error(_) => assert_true(true)
      | Ok(_) => assert_true(false)
      }
      // rm must NEVER have been called
      assert_true(rmCalls.contents->Array.length == 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      assert_true(rmCalls.contents->Array.length == 0)
      resolve()
      Promise.resolve()
    })->ignore
  })
}

// Step 4b: rollback allows staging dir within tmpdir (normal case)
let testRollbackAllowsInTmpdir = () => {
  testAsync("rollback: allows rm of staging dir within tmpdir", resolve => {
    let rmCalls: ref<array<string>> = ref([])
    let baseFs = NodeJsFileSystem.make()

    let mockFs: Ports.fileSystem = {
      readFile: baseFs.readFile,
      writeFile: baseFs.writeFile,
      mkdir: baseFs.mkdir,
      rm: (target, ~options as _=?) => {
        rmCalls.contents->Array.push(target)->ignore
        Promise.resolve()
      },
      cp: baseFs.cp,
      readdir: baseFs.readdir,
      fileExists: _ => Promise.resolve(false),
      stat: _path => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
      realpath: path => Promise.resolve(path),
      makeStagingDir: baseFs.makeStagingDir,
    }

    // /tmp/blueprint-xxx is within /tmp — must succeed
    Commit.rollback(
      "/tmp/blueprint-test-staging",
      ~tmpRoot="/tmp",
      ~path=NodeJsPath.make(),
      ~fs=mockFs,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_true(true)
      | Error(_) => assert_true(false)
      }
      // rm SHOULD have been called
      assert_true(rmCalls.contents->Array.length > 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      assert_true(false)
      resolve()
      Promise.resolve()
    })->ignore
  })
}

let suite = () => {
  suite("Commit rollbackOutput containment", () => {
    testRollbackOutputDeniesOutOfTree()
    testRollbackOutputAllowsInTree()
  })
  suite("Commit rollback tmpdir assertion", () => {
    testRollbackDeniesNonTmpdir()
    testRollbackAllowsInTmpdir()
  })
}

suite()
