// PathTraversal_test — malicious path traversal tests

open TestHelpers
open Ports

let makeMockFs = (): Ports.fileSystem => {
  readFile: (_, ~options=?) => Promise.resolve(""),
  writeFile: (_, _, ~options=?) => Promise.resolve(),
  mkdir: (_, ~options=?) => Promise.resolve(""),
  rm: (_, ~options=?) => Promise.resolve(),
  cp: (_, _, ~options=?) => Promise.resolve(),
  readdir: (_, ~options=?) => Promise.resolve([]),
  fileExists: _ => Promise.resolve(false),
  stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true}: Ports.statResult),
  makeStagingDir: () => "/tmp/test",
  realpath: path => Promise.resolve(path),
}

let runIsWithinTree = (path, root, pathAdapter) => {
  let mockFs = makeMockFs()
  PathSecurity.isWithinTree(path, root, pathAdapter, mockFs)
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
})
