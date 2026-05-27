// test/Ports_test.res
open TestHelpers
open Ports

suite("Ports", () => {
  test("fileSystem: has all required fields", () => {
    let fs: Ports.fileSystem = {
      readFile: (_, ~options=?) => Promise.resolve(""),
      writeFile: (_, _, ~options=?) => Promise.resolve(),
      mkdir: (_, ~options=?) => Promise.resolve(""),
      rm: (_, ~options=?) => Promise.resolve(),
      cp: (_, _, ~options=?) => Promise.resolve(),
      readdir: (_, ~options=?) => Promise.resolve([]),
      fileExists: _ => Promise.resolve(false),
      stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true}),
      makeStagingDir: () => "/tmp/test",
      realpath: path => Promise.resolve(path),
    }
    assert_true(true)
  })

  test("process: has all required fields", () => {
    let proc: Ports.process = {
      cwd: () => "/home/user",
      env: () => Dict.make(),
      argv: () => ["node", "main.mjs"],
      exit: _ => (),
    }
    assert_true(true)
  })

  test("execResult: has expected shape", () => {
    let result: Ports.execResult = {stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}
    assert_eq(result.status, Some(0))
    assert_eq(result.signalCode, None)
    assert_eq(result.killed, false)
  })

  test("shellOptions: optional fields work", () => {
    let opts: shellOptions = {cwd: "/tmp", env: Dict.make(), timeout: 30}
    assert_eq(opts.cwd, Some("/tmp"))
    assert_eq(opts.timeout, Some(30))
  })

  test("shell: has execShellCommand, execAsync, execFileAsync", () => {
    let shell: Ports.shell = {
      execShellCommand: (~command, ~cwd=?) => Promise.resolve(Ok("")),
      execAsync: (_, ~options=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
      execFileAsync: (_, ~args=?, ~options=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
    }
    assert_true(true)
  })

  test("path: has join, resolve, dirname, isAbsolute, basename", () => {
    let p: Ports.path = {
      join: (a, b) => a ++ "/" ++ b,
      resolve: (a, b) => a ++ "/" ++ b,
      dirname: s => s,
      isAbsolute: s => String.startsWith(s, "/"),
      basename: (s, ~ext=?) => s,
    }
    assert_true(true)
  })

  test("interactiveIO: has ask, askConfirm, close", () => {
    let io: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question, ~defaultYes=?) => Promise.resolve(false),
      close: () => (),
    }
    assert_true(true)
  })

  test("parsedArgs: has values dict and positionals array", () => {
    let args: Ports.parsedArgs = {values: Dict.make(), positionals: []}
    assert_true(args.values->Dict.size >= 0)
    assert_true(Array.length(args.positionals) >= 0)
  })

  test("argParser: has parse function", () => {
    let parser: Ports.argParser = {
      parse: (~args, ~strict, ~allowPositionals) => Ok({values: Dict.make(), positionals: []}),
    }
    assert_true(true)
  })

  test("deps: bundles all ports", () => {
    let deps: Ports.deps = {
      fs: {
        readFile: (_, ~options=?) => Promise.resolve(""),
        writeFile: (_, _, ~options=?) => Promise.resolve(),
        mkdir: (_, ~options=?) => Promise.resolve(""),
        rm: (_, ~options=?) => Promise.resolve(),
        cp: (_, _, ~options=?) => Promise.resolve(),
        readdir: (_, ~options=?) => Promise.resolve([]),
        fileExists: _ => Promise.resolve(false),
stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true} : statResult),
        makeStagingDir: () => "/tmp/test",
        realpath: path => Promise.resolve(path),
      },
      path: {
        join: (a, b) => a ++ "/" ++ b,
        resolve: (a, b) => a ++ "/" ++ b,
        dirname: s => s,
        isAbsolute: s => String.startsWith(s, "/"),
        basename: (s, ~ext=?) => s,
      },
      process: {
        cwd: () => "/home/user",
        env: () => Dict.make(),
        argv: () => ["node"],
        exit: _ => (),
      },
      shell: {
        execShellCommand: (~command, ~cwd=?) => Promise.resolve(Ok("")),
        execAsync: (_, ~options=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
        execFileAsync: (_, ~args=?, ~options=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
      },
      interactiveIO: {
        ask: _ => Promise.resolve(""),
        askConfirm: (~question, ~defaultYes=?) => Promise.resolve(false),
        close: () => (),
      },
      argParser: {
        parse: (~args, ~strict, ~allowPositionals) => Ok({values: Dict.make(), positionals: []}),
      },
    }
    assert_true(true)
  })
})