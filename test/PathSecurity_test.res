// PathSecurity_test — unit tests for path traversal protection

open TestHelpers
open Ports

// A mock filesystem that returns paths as-is (identity realpath).
// This is sufficient for testing path traversal scenarios since
// those don't involve actual symlinks.
let makeMockFs = (): Ports.fileSystem => {
  readFile: (_, ~options as _=?) => Promise.resolve(""),
  writeFile: (_, _, ~options as _=?) => Promise.resolve(),
  mkdir: (_, ~options as _=?) => Promise.resolve(""),
  rm: (_, ~options as _=?) => Promise.resolve(),
  cp: (_, _, ~options as _=?) => Promise.resolve(),
  readdir: (_, ~options as _=?) => Promise.resolve([]),
  fileExists: _ => Promise.resolve(false),
  stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
  realpath: path => Promise.resolve(path),
}

let runTests = (label, pathAdapter) => {
  suite(`PathSecurity [${label}]`, () => {
    testAsync("isWithinTree: path inside tree returns true", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/project/src", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_true(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: path outside tree returns false", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/other", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_false(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: path traversal attempt returns false", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/project/../../../etc/passwd", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_false(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: absolute path inside returns true", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/project", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_true(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: absolute path outside returns false", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/etc/passwd", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_false(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: sibling path returns false", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/project-sibling", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_false(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: deep nested path inside returns true", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/project/src/components/Button/index.tsx", "/home/user/project", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_true(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })

    testAsync("isWithinTree: traversal to parent of root returns false", resolve => {
      let mockFs = makeMockFs()
      PathSecurity.isWithinTree("/home/user/../../../etc/passwd", "/home/user", pathAdapter, mockFs)
      ->Promise.then(result => {
        assert_false(result)
        resolve()
        Promise.resolve()
      })
      ->Promise.catch(_ => { resolve(); Promise.resolve() })->ignore
    })
  })
}

runTests("Node.js", NodeJsPath.make())
runTests("Deno", DenoPath.make())

// Real filesystem test: symlink bypass detection
suite("PathSecurity Symlink", () => {
  testAsync("isWithinTree: symlink to outside is rejected", resolve => {
    let fs = NodeJsFileSystem.make()
    let pathAdapter = NodeJsPath.make()
    let tmpDir = NodeJs.Os.makeStagingDir()

    // Create: tmpDir/link -> /etc
    let linkTarget = "/etc"
    let linkPath = pathAdapter.join(tmpDir, "link")
    let _ = NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})

    NodeJs.Fs.mkdir(tmpDir, ~options={recursive: true})
    ->Promise.then(_ => {
      // Create symlink using shell command
      let shell: Ports.shell = NodeJsShell.make()
      shell.execShellCommand(~command="ln -s " ++ linkTarget ++ " " ++ linkPath)
    })
    ->Promise.then(_ => {
      // Try to access /etc/passwd via the symlink
      let evilPath = pathAdapter.join(linkPath, "passwd")
      PathSecurity.isWithinTree(evilPath, tmpDir, pathAdapter, fs)
    })
    ->Promise.then(result => {
      // The symlink resolves to /etc, which is outside tmpDir
      assert_false(result)
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })->ignore
  })
})