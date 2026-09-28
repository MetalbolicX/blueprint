// test/Ports_test.res
open TestHelpers
open Ports

suite("Ports", () => {
  test("fileSystem: has all required fields", () => {
    let _fs: Ports.fileSystem = {
      readFile: (_, ~options as _=?) => Promise.resolve(""),
      writeFile: (_, _, ~options as _=?) => Promise.resolve(),
      mkdir: (_, ~options as _=?) => Promise.resolve(""),
      rm: (_, ~options as _=?) => Promise.resolve(),
      cp: (_, _, ~options as _=?) => Promise.resolve(),
      readdir: (_, ~options as _=?) => Promise.resolve([]),
      fileExists: _ => Promise.resolve(false),
      stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true, isSymbolicLink: () => false}),
      lstat: _ => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false}),
      realpath: path => Promise.resolve(path),
      makeStagingDir: prefix => Promise.resolve("/tmp/" ++ prefix ++ "-test"),
    }
    assert_true(true)
  })

  test("process: has all required fields", () => {
    let handledSignals = ref([])
    let removedListeners = ref(false)
    let proc: Ports.process = {
      cwd: () => "/home/user",
      env: () => Dict.make(),
      argv: () => ["node", "main.mjs"],
      exit: _ => (),
      onSignal: (signal, callback) => {
        handledSignals := Array.concat(handledSignals.contents, [signal])
        callback()
      },
      removeSignalListeners: () => removedListeners := true,
      homedir: () => "/home/user",
    }

    proc.onSignal("SIGINT", () => handledSignals := Array.concat(handledSignals.contents, ["handled:SIGINT"]))
    proc.onSignal("SIGTERM", () => handledSignals := Array.concat(handledSignals.contents, ["handled:SIGTERM"]))
    proc.removeSignalListeners()

    assert_eq(Array.get(handledSignals.contents, 0), Some("SIGINT"))
    assert_eq(Array.get(handledSignals.contents, 1), Some("handled:SIGINT"))
    assert_eq(Array.get(handledSignals.contents, 2), Some("SIGTERM"))
    assert_eq(Array.get(handledSignals.contents, 3), Some("handled:SIGTERM"))
    assert_true(removedListeners.contents)
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
    let _shell: Ports.shell = {
      execShellCommand: (~command as _, ~cwd as _=?, ~timeout as _=?) => Promise.resolve(Ok("")),
      execAsync: (_, ~options as _=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
      execFileAsync: (_, ~args as _=?, ~options as _=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
    }
    assert_true(true)
  })

  test("path: has join, resolve, dirname, isAbsolute, basename", () => {
    let _p: Ports.path = {
      join: (a, b) => a ++ "/" ++ b,
      resolve: (a, b) => a ++ "/" ++ b,
      dirname: s => s,
      isAbsolute: s => String.startsWith(s, "/"),
      basename: (s, ~ext as _=?) => s,
    }
    assert_true(true)
  })

  test("interactiveIO: has ask, askConfirm, close", () => {
    let _io: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(false),
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
    let _parser: Ports.argParser = {
      parse: (~args as _, ~strict as _, ~allowPositionals as _) => Ok({values: Dict.make(), positionals: []}),
    }
    assert_true(true)
  })

  test("deps: bundles all ports", () => {
    let _deps: Ports.deps = {
      fs: {
        readFile: (_, ~options as _=?) => Promise.resolve(""),
        writeFile: (_, _, ~options as _=?) => Promise.resolve(),
        mkdir: (_, ~options as _=?) => Promise.resolve(""),
        rm: (_, ~options as _=?) => Promise.resolve(),
        cp: (_, _, ~options as _=?) => Promise.resolve(),
        readdir: (_, ~options as _=?) => Promise.resolve([]),
        fileExists: _ => Promise.resolve(false),
        stat: _ => Promise.resolve({isDirectory: () => false, isFile: () => true, isSymbolicLink: () => false} : statResult),
        lstat: _ => Promise.resolve({isDirectory: () => false, isFile: () => false, isSymbolicLink: () => false} : statResult),
        realpath: path => Promise.resolve(path),
        makeStagingDir: prefix => Promise.resolve("/tmp/" ++ prefix ++ "-test"),
      },
      path: {
        join: (a, b) => a ++ "/" ++ b,
        resolve: (a, b) => a ++ "/" ++ b,
        dirname: s => s,
        isAbsolute: s => String.startsWith(s, "/"),
        basename: (s, ~ext as _=?) => s,
      },
      process: {
        cwd: () => "/home/user",
        env: () => Dict.make(),
        argv: () => ["node"],
        exit: _ => (),
        onSignal: (_signal, callback) => callback(),
        removeSignalListeners: () => (),
        homedir: () => "/home/user",
      },
      shell: {
        execShellCommand: (~command as _, ~cwd as _=?, ~timeout as _=?) => Promise.resolve(Ok("")),
        execAsync: (_, ~options as _=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
        execFileAsync: (_, ~args as _=?, ~options as _=?) => Promise.resolve({stdout: "", stderr: "", status: Some(0), signalCode: None, killed: false}),
      },
      interactiveIO: {
        ask: _ => Promise.resolve(""),
        askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(false),
        close: () => (),
      },
      argParser: {
        parse: (~args as _, ~strict as _, ~allowPositionals as _) => Ok({values: Dict.make(), positionals: []}),
      },
      yamlParser: {
        parse: s => Ok(Bindings.Yaml.parse(s)),
      },
      ejs: {
        renderString: (~template as _, ~context as _) => Ok("rendered"),
        renderFile: (~path as _, ~context as _) => Promise.resolve(Ok("rendered")),
      },
    }
    assert_true(true)
  })
})
