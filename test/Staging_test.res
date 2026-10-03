// Staging_test — unit tests for Staging phase1 operations

open TestHelpers
open Ports

// Mock path adapter for tests (mirrors Node.js path behavior for simple cases)
let mockPath: Ports.path = {
  join: (a, b) => {
    let a1 = if a->String.endsWith("/") { a->String.slice(~start=0, ~end=-1) } else { a }
    let b1 = if b->String.startsWith("/") { b->String.slice(~start=1, ~end=-1) } else { b }
    a1 ++ "/" ++ b1
  },
  resolve: (a, _b) => a,
  dirname: path => {
    let parts = String.split(path, "/")
    if Array.length(parts) <= 1 {
      "."
    } else {
      let dirParts = parts->Array.slice(~start=0, ~end=Array.length(parts) - 1)
      let dir = dirParts->Array.join("/")
      if dir == "" { "." } else { dir }
    }
  },
  isAbsolute: path => String.startsWith(path, "/"),
  basename: (path, ~ext as _=?) => {
    let parts = String.split(path, "/")
    parts->Array.get(Array.length(parts) - 1)->Option.getOr(path)
  },
}

// Step 2: test that writeStagedFile rejects paths that escape the staging dir
//
// Uses NodeJsPath.resolve in the mock realpath to properly normalize paths.
// Without this, a path like /tmp/s/../../etc/evil would pass the isBoundary
// string-prefix check because it literally starts with "/tmp/s/", but a real
// realpath would resolve it to /etc/evil which is outside /tmp/s.
let testWriteStagedFileDeniesTraversal = () => {
  testAsync("writeStagedFile: traversal targetPath is rejected and writeFile not called", resolve => {
    let writeFileCalls: ref<array<string>> = ref([])
    let writeFile = (path, _content, ~options as _=?) => {
      writeFileCalls.contents->Array.push(path)->ignore
      Promise.resolve()
    }
    let mkdir = (_path, ~options as _=?) => Promise.resolve("")
    // Use NodeJsPath.resolve to properly normalize .. components
    let nodePath = NodeJsPath.make()
    let realpath = path => Promise.resolve(nodePath.resolve(path, ""))
    let stat = _path => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult)
    let lstat = _path => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false}: Ports.lstatResult)

    let mockFs: Ports.fileSystem = {
      readFile: (_, ~options as _=?) => Promise.resolve(""),
      writeFile: writeFile,
      mkdir: mkdir,
      rm: (_, ~options as _=?) => Promise.resolve(),
      cp: (_, _, ~options as _=?) => Promise.resolve(),
      readdir: (_, ~options as _=?) => Promise.resolve([]),
      fileExists: _ => Promise.resolve(false),
      stat: stat,
      lstat: lstat,
      realpath: realpath,
      makeStagingDir: _prefix => Promise.resolve("/tmp/blueprint-test"),
    }

    // stagingDir must be an absolute path for the resolve-based realpath to work correctly
    Staging.writeStagedFile(
      ~stagingDir=nodePath.resolve("/tmp", "s"),
      ~targetPath="../../etc/evil",
      ~renderedBody="evil content",
      ~path=mockPath,
      ~pathSecurity=TestPorts.stubPathSecurity,
      ~fs=mockFs,
    )
    ->Promise.then(result => {
      // Must return Error (path escapes staging directory)
      switch result {
      | Error(_) => assert_true(true)
      | Ok(_) => assert_true(false) // should NOT succeed
      }
      // writeFile must NEVER have been called
      assert_true(writeFileCalls.contents->Array.length == 0)
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      // An exception is also acceptable (but Error is preferred)
      assert_true(writeFileCalls.contents->Array.length == 0)
      resolve()
      Promise.resolve()
    })->ignore
  })
}

// Step 2b: writeStagedFile allows normal in-tree paths
let testWriteStagedFileAcceptsInTreePath = () => {
  testAsync("writeStagedFile: normal in-tree targetPath succeeds", resolve => {
    let writeFileCalls: ref<array<string>> = ref([])
    let writeFile = (path, _content, ~options as _=?) => {
      writeFileCalls.contents->Array.push(path)->ignore
      Promise.resolve()
    }
    let mkdir = (_path, ~options as _=?) => Promise.resolve("")
    let nodePath = NodeJsPath.make()
    let realpath = path => Promise.resolve(nodePath.resolve(path, ""))

    let mockFs: Ports.fileSystem = {
      readFile: (_, ~options as _=?) => Promise.resolve(""),
      writeFile: writeFile,
      mkdir: mkdir,
      rm: (_, ~options as _=?) => Promise.resolve(),
      cp: (_, _, ~options as _=?) => Promise.resolve(),
      readdir: (_, ~options as _=?) => Promise.resolve([]),
      fileExists: _ => Promise.resolve(false),
      stat: _path => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
      lstat: _path => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false}: Ports.lstatResult),
      realpath: realpath,
      makeStagingDir: _prefix => Promise.resolve("/tmp/blueprint-test"),
    }

    Staging.writeStagedFile(
      ~stagingDir=nodePath.resolve("/tmp", "s"),
      ~targetPath="src/index.ts",
      ~renderedBody="export const x = 1",
      ~path=mockPath,
      ~pathSecurity=TestPorts.stubPathSecurity,
      ~fs=mockFs,
    )
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_true(true)
      | Error(_) => assert_true(false) // should not fail
      }
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

let testMakeStagingDirUsesExclusivePrivateDirectories = () => {
  testAsync("makeStagingDir: honors prefix, creates unique existing 0700 directories", resolve => {
    let fs = NodeJsFileSystem.make()
    let ts = Date.now()->Float.toInt->Int.toString
    let prefix = "blueprint-" ++ ts ++ "-"
    fs.makeStagingDir(prefix)
    ->Promise.then(first => {
      fs.makeStagingDir(prefix)
      ->Promise.then(second => {
        assert_true(first != second)
        let expectedPrefix = NodeJs.Path.join(NodeJs.Os.tmpdir(), prefix)
        assert_true(first->String.startsWith(expectedPrefix))
        assert_true(second->String.startsWith(expectedPrefix))
        Promise.all([fs.fileExists(first), fs.fileExists(second)])
        ->Promise.then(exists => {
          assert_true(Array.get(exists, 0)->Option.getOr(false))
          assert_true(Array.get(exists, 1)->Option.getOr(false))
          NodeJs.Fs.stat(first)->Promise.then(stat => {
            let isPosix: bool = %raw(`process.platform !== "win32"`)
            if isPosix {
              let mode: int = Obj.magic(stat)["mode"]
              let permissionBits: int => int = %raw("mode => mode & 0o777")
              assert_eq(permissionBits(mode), 0o700)
            }
            Promise.all([
              NodeJs.Fs.rm(first, ~options={recursive: true}),
              NodeJs.Fs.rm(second, ~options={recursive: true}),
            ])
            ->Promise.then(_ => { resolve(); Promise.resolve() })
          })
        })
      })
    })
    ->Promise.catch(_ => { assert_false(true); resolve(); Promise.resolve() })->ignore
  })
}

let suite = () => {
  suite("Staging", () => {
    testWriteStagedFileDeniesTraversal()
    testWriteStagedFileAcceptsInTreePath()
    testMakeStagingDirUsesExclusivePrivateDirectories()
  })
}

suite()
