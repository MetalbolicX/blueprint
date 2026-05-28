open TestHelpers

let installProcessSignalSpy: unit => unit = %raw(`
  function() {
    globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLS__ = [];
    globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLBACKS__ = {};
    globalThis.__BLUEPRINT_ORIGINAL_PROCESS_ON__ = process.on;
    globalThis.__BLUEPRINT_ORIGINAL_PROCESS_REMOVE_ALL_LISTENERS__ = process.removeAllListeners;
    process.on = function(signal, callback) {
      globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLS__.push("on:" + signal);
      globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLBACKS__[signal] = callback;
      return process;
    };
    process.removeAllListeners = function() {
      globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLS__.push("removeAllListeners");
      globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLBACKS__ = {};
      return process;
    };
  }
`)

let restoreProcessSignalSpy: unit => unit = %raw(`
  function() {
    if (globalThis.__BLUEPRINT_ORIGINAL_PROCESS_ON__) {
      process.on = globalThis.__BLUEPRINT_ORIGINAL_PROCESS_ON__;
      delete globalThis.__BLUEPRINT_ORIGINAL_PROCESS_ON__;
    }
    if (globalThis.__BLUEPRINT_ORIGINAL_PROCESS_REMOVE_ALL_LISTENERS__) {
      process.removeAllListeners = globalThis.__BLUEPRINT_ORIGINAL_PROCESS_REMOVE_ALL_LISTENERS__;
      delete globalThis.__BLUEPRINT_ORIGINAL_PROCESS_REMOVE_ALL_LISTENERS__;
    }
    delete globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLS__;
    delete globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLBACKS__;
  }
`)

let getProcessSignalCalls: unit => array<string> = %raw(`
  function() {
    return globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLS__ || [];
  }
`)

let invokeProcessSignal: string => unit = %raw(`
  function(signal) {
    globalThis.__BLUEPRINT_PROCESS_SIGNAL_CALLBACKS__[signal]();
  }
`)

suite("NodeJsProcess adapter", () => {
  test("cwd returns current working directory", () => {
    let p = NodeJsProcess.make()
    let cwd = p.cwd()
    assert_true(String.length(cwd) > 0)
  })

  test("env returns process environment variables", () => {
    let p = NodeJsProcess.make()
    assert_true(Dict.size(p.env()) >= 0)
  })

  test("argv returns command line arguments", () => {
    let p = NodeJsProcess.make()
    let argv = p.argv()
    assert_true(Array.length(argv) >= 1)
    switch Array.get(argv, 0) {
    | Some(first) => assert_true(String.endsWith(first, "node"))
    | None => assert_true(false)
    }
  })

  test("onSignal registers handlers and removeSignalListeners clears them", () => {
    installProcessSignalSpy()

    let receivedSignals = ref([])
    let p = NodeJsProcess.make()
    p.onSignal("SIGINT", () => receivedSignals := Array.concat(receivedSignals.contents, ["SIGINT"]))
    p.onSignal("SIGTERM", () => receivedSignals := Array.concat(receivedSignals.contents, ["SIGTERM"]))
    invokeProcessSignal("SIGINT")
    invokeProcessSignal("SIGTERM")
    p.removeSignalListeners()

    let calls = getProcessSignalCalls()
    assert_eq(Array.get(calls, 0), Some("on:SIGINT"))
    assert_eq(Array.get(calls, 1), Some("on:SIGTERM"))
    assert_eq(Array.get(calls, 2), Some("removeAllListeners"))
    assert_eq(Array.get(receivedSignals.contents, 0), Some("SIGINT"))
    assert_eq(Array.get(receivedSignals.contents, 1), Some("SIGTERM"))

    restoreProcessSignalSpy()
  })
})
