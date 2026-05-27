open TestHelpers

suite("NodeJsFileSystem adapter", () => {
  let fs = NodeJsFileSystem.make()

  testAsync("makeStagingDir creates a writable directory", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    assert_true(String.length(dir) > 0)
    fs.writeFile(NodeJs.Path.join(dir, "test.txt"), "hello")
    ->Promise.then(_ => fs.fileExists(NodeJs.Path.join(dir, "test.txt")))
    ->Promise.then(exists => {
      assert_true(exists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("writeFile + readFile roundtrip", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let filePath = NodeJs.Path.join(dir, "data.txt")
    let content = "Hello, World!"
    fs.writeFile(filePath, content)
    ->Promise.then(_ => fs.readFile(filePath, ~options={encoding: "utf8"}))
    ->Promise.then(result => {
      assert_eq(result, content)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("mkdir creates directory", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let subDir = NodeJs.Path.join(dir, "subdir")
    fs.mkdir(subDir)
    ->Promise.then(_ => fs.fileExists(subDir))
    ->Promise.then(exists => {
      assert_true(exists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("readdir lists directory contents", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let filePath = NodeJs.Path.join(dir, "a.txt")
    let nestedDir = NodeJs.Path.join(dir, "sub")
    fs.writeFile(filePath, "a")
    ->Promise.then(_ => fs.mkdir(nestedDir))
    ->Promise.then(_ => fs.readdir(dir))
    ->Promise.then(entries => {
      assert_true(Array.includes(entries, "a.txt"))
      assert_true(Array.includes(entries, "sub"))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("fileExists returns false for missing file", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    fs.fileExists(NodeJs.Path.join(dir, "nonexistent"))
    ->Promise.then(exists => {
      assert_false(exists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("stat returns correct file info", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let filePath = NodeJs.Path.join(dir, "info.txt")
    fs.writeFile(filePath, "test")
    ->Promise.then(_ => fs.stat(filePath))
    ->Promise.then(s => {
      assert_false(s.isDirectory())
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("rm deletes file", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let filePath = NodeJs.Path.join(dir, "delete_me.txt")
    fs.writeFile(filePath, "bye")
    ->Promise.then(_ => fs.rm(filePath))
    ->Promise.then(_ => fs.fileExists(filePath))
    ->Promise.then(exists => {
      assert_false(exists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("cp copies file", resolve => {
    let dir = NodeJs.Os.makeStagingDir()
    let src = NodeJs.Path.join(dir, "src.txt")
    let dst = NodeJs.Path.join(dir, "dst.txt")
    fs.writeFile(src, "copy me")
    ->Promise.then(_ => fs.cp(src, dst))
    ->Promise.then(_ => fs.fileExists(dst))
    ->Promise.then(exists => {
      assert_true(exists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
