open TestHelpers

let setupMock: unit => unit = %raw(`
  function() {
    globalThis.__EXIT_CODE = undefined;
    globalThis.__BLUEPRINT_DENO_SIGNAL_CALLS__ = [];
    globalThis.__BLUEPRINT_DENO_SIGNAL_CALLBACKS__ = {};
    globalThis.Deno = {
      cwd: () => "/mock/cwd",
      env: {
        toObject: () => ({ MOCK_ENV: "true" })
      },
      args: ["--force", "my-arg"],
      exit: (code) => { globalThis.__EXIT_CODE = code; },
      addSignalListener: (signal, callback) => {
        globalThis.__BLUEPRINT_DENO_SIGNAL_CALLS__.push("add:" + signal);
        globalThis.__BLUEPRINT_DENO_SIGNAL_CALLBACKS__[signal] = callback;
      },
      removeSignalListener: (signal, callback) => {
        globalThis.__BLUEPRINT_DENO_SIGNAL_CALLS__.push("remove:" + signal);
        if (globalThis.__BLUEPRINT_DENO_SIGNAL_CALLBACKS__[signal] === callback) {
          delete globalThis.__BLUEPRINT_DENO_SIGNAL_CALLBACKS__[signal];
        }
      }
    };
  }
`)

let teardownMock: unit => unit = %raw(`
  function() {
    delete globalThis.Deno;
    delete globalThis.__EXIT_CODE;
    delete globalThis.__BLUEPRINT_DENO_SIGNAL_CALLS__;
    delete globalThis.__BLUEPRINT_DENO_SIGNAL_CALLBACKS__;
  }
`)

let getSignalCalls: unit => array<string> = %raw(`
  function() {
    return globalThis.__BLUEPRINT_DENO_SIGNAL_CALLS__ || [];
  }
`)

let invokeSignal: string => unit = %raw(`
  function(signal) {
    globalThis.__BLUEPRINT_DENO_SIGNAL_CALLBACKS__[signal]();
  }
`)

suite("DenoProcess adapter", () => {
  test("implements process operations", () => {
    setupMock()

    let p = DenoProcess.make()

    assert_eq(p.cwd(), "/mock/cwd")

    let env = p.env()
    assert_eq(Dict.get(env, "MOCK_ENV"), Some("true"))

    let argv = p.argv()
    assert_eq(Array.get(argv, 0), Some("deno"))
    assert_eq(Array.get(argv, 1), Some("blueprint"))
    assert_eq(Array.get(argv, 2), Some("--force"))
    assert_eq(Array.get(argv, 3), Some("my-arg"))

    p.exit(42)
    let exitCode = %raw(`globalThis.__EXIT_CODE`)
    assert_eq(exitCode, 42)

    let receivedSignals = ref([])
    p.onSignal("SIGINT", () => receivedSignals := Array.concat(receivedSignals.contents, ["SIGINT"]))
    p.onSignal("SIGTERM", () => receivedSignals := Array.concat(receivedSignals.contents, ["SIGTERM"]))
    invokeSignal("SIGINT")
    invokeSignal("SIGTERM")
    p.removeSignalListeners()

    let calls = getSignalCalls()
    assert_eq(Array.get(calls, 0), Some("add:SIGINT"))
    assert_eq(Array.get(calls, 1), Some("add:SIGTERM"))
    assert_eq(Array.get(calls, 2), Some("remove:SIGINT"))
    assert_eq(Array.get(calls, 3), Some("remove:SIGTERM"))
    assert_eq(Array.get(receivedSignals.contents, 0), Some("SIGINT"))
    assert_eq(Array.get(receivedSignals.contents, 1), Some("SIGTERM"))

    teardownMock()
  })
})
