// Router_test — unit tests for Router.extractAttributes

open TestHelpers

let installConsoleLogSpy: unit => unit = %raw(`
  function() {
    globalThis.__testMessages = [];
    globalThis.__originalConsoleLog = console.log;
    console.log = function(msg) { globalThis.__testMessages.push(msg); };
  }
`)

let restoreConsoleLog: unit => unit = %raw(`
  function() {
    if (globalThis.__originalConsoleLog) {
      console.log = globalThis.__originalConsoleLog;
      delete globalThis.__originalConsoleLog;
    }
  }
`)

let makeProbeDeps = (~exitCodes: ref<array<int>>): Ports.deps => {
  fs: NodeJsFileSystem.make(),
  path: NodeJsPath.make(),
  process: {
    cwd: () => ".",
    env: () => Dict.make(),
    argv: () => ["node", "blueprint"],
    exit: code => exitCodes.contents = Array.concat(exitCodes.contents, [code]),
    onSignal: (_, _) => (),
    removeSignalListeners: () => (),
    homedir: () => "/tmp/test-home",
  },
  shell: NodeJsShell.make(),
  interactiveIO: {
    ask: _ => Promise.resolve(""),
    askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(false),
    close: () => (),
  },
  argParser: {
    parse: (~args as _, ~strict as _, ~allowPositionals as _) =>
      Ok({values: Dict.make(), positionals: []}),
  },
  yamlParser: NodeJsYamlParser.make(),
  ejs: NodeJsEjs.make(),
}

suite("Router extractAttributes", () => {
  test("extracts --key=value", () => {
    let result = Router.extractAttributes(~args=["--myVar=hello"])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "hello")
    | _ => assert_false(true)
    }
  })

  test("extracts --key value", () => {
    let result = Router.extractAttributes(~args=["--myVar", "hello"])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "hello")
    | _ => assert_false(true)
    }
  })

  test("extracts --key as boolean true", () => {
    let result = Router.extractAttributes(~args=["--flag"])
    switch Dict.get(result, "flag") {
    | Some(Scalar(v)) => assert_eq(v, "true")
    | _ => assert_false(true)
    }
  })

  test("skips known flags (name, force, output, help)", () => {
    let result = Router.extractAttributes(~args=["--name=foo", "--force", "--output=./dist", "--help", "--myVar=bar"])
    // name, force, output, help should NOT be in the result
    assert_eq(Dict.get(result, "name"), None)
    assert_eq(Dict.get(result, "force"), None)
    assert_eq(Dict.get(result, "output"), None)
    assert_eq(Dict.get(result, "help"), None)
    // myVar SHOULD be in the result
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "bar")
    | _ => assert_false(true)
    }
  })

  test("stops parsing at -- terminator", () => {
    let result = Router.extractAttributes(~args=["--myVar=hello", "--", "--other=ignored"])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "hello")
    | _ => assert_false(true)
    }
    switch Dict.get(result, "other") {
    | None => assert_eq(Dict.get(result, "other"), None)
    | Some(_) => assert_false(true)
    }
  })

  test("accumulates multiple values for the same key", () => {
    let result = Router.extractAttributes(~args=["--items=a", "--items=b", "--items=c"])
    switch Dict.get(result, "items") {
    | Some(Values(arr)) => {
        assert_eq(Array.length(arr), 3)
        switch arr[0] { | Some(v) => assert_eq(v, "a") | None => assert_false(true) }
        switch arr[1] { | Some(v) => assert_eq(v, "b") | None => assert_false(true) }
        switch arr[2] { | Some(v) => assert_eq(v, "c") | None => assert_false(true) }
      }
    | _ => assert_false(true)
    }
  })

  test("handles empty args", () => {
    let result = Router.extractAttributes(~args=[])
    assert_eq(Dict.toArray(result)->Array.length, 0)
  })

  test("handles --key= (empty string value)", () => {
    let result = Router.extractAttributes(~args=["--myVar="])
    switch Dict.get(result, "myVar") {
    | Some(Scalar(v)) => assert_eq(v, "")
    | _ => assert_false(true)
    }
  })

  test("Help usage mentions healthz and readyz", () => {
    installConsoleLogSpy()
    Help.printUsage()
    let msgs: array<string> = %raw("globalThis.__testMessages")
    assert_true(Array.some(msgs, msg => String.includes(msg, "healthz")))
    assert_true(Array.some(msgs, msg => String.includes(msg, "readyz")))
    restoreConsoleLog()
  })

  testAsync("healthz routes to liveness output and exits 0", resolve => {
    installConsoleLogSpy()
    let exitCodes = ref([])
    let deps = makeProbeDeps(~exitCodes)

    Router.route(~deps, ~args=["healthz"])
    ->Promise.then(_ => {
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_eq(Array.length(msgs), 1)
      switch Array.get(msgs, 0) {
      | Some(msg) => assert_eq(msg, "{\"status\":\"ok\"}")
      | None => assert_false(true)
      }
      assert_eq(exitCodes.contents->Array.length, 1)
      assert_eq(exitCodes.contents[0], Some(0))
      restoreConsoleLog()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreConsoleLog()
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("readyz reports not_ready before ProbeState.setReady", resolve => {
    ProbeState.reset()
    installConsoleLogSpy()
    let exitCodes = ref([])
    let deps = makeProbeDeps(~exitCodes)

    Router.route(~deps, ~args=["readyz"])
    ->Promise.then(_ => {
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_eq(Array.length(msgs), 1)
      switch Array.get(msgs, 0) {
      | Some(msg) => assert_eq(msg, "{\"status\":\"not_ready\"}")
      | None => assert_false(true)
      }
      assert_eq(exitCodes.contents->Array.length, 1)
      assert_eq(exitCodes.contents[0], Some(0))
      restoreConsoleLog()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreConsoleLog()
      ProbeState.reset()
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("readyz reports ready after ProbeState.setReady", resolve => {
    installConsoleLogSpy()
    let exitCodes = ref([])
    let deps = makeProbeDeps(~exitCodes)
    ProbeState.setReady()

    Router.route(~deps, ~args=["readyz"])
    ->Promise.then(_ => {
      let msgs: array<string> = %raw("globalThis.__testMessages")
      assert_eq(Array.length(msgs), 1)
      switch Array.get(msgs, 0) {
      | Some(msg) => assert_eq(msg, "{\"status\":\"ready\"}")
      | None => assert_false(true)
      }
      assert_eq(exitCodes.contents->Array.length, 1)
      assert_eq(exitCodes.contents[0], Some(0))
      restoreConsoleLog()
      ProbeState.reset()
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      restoreConsoleLog()
      ProbeState.reset()
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
