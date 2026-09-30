open TestHelpers

let captureConsoleLog: unit => unit = %raw(`
  function() {
    globalThis.__helpLogs = [];
    globalThis.__helpOriginalLog = console.log;
    console.log = message => globalThis.__helpLogs.push(message);
  }
`)

let restoreConsoleLog: unit => unit = %raw(`
  function() {
    console.log = globalThis.__helpOriginalLog;
    delete globalThis.__helpOriginalLog;
  }
`)

let captureConsoleError: unit => unit = %raw(`
  function() {
    globalThis.__helpErrors = [];
    globalThis.__helpOriginalError = console.error;
    console.error = message => globalThis.__helpErrors.push(message);
  }
`)

let restoreConsoleError: unit => unit = %raw(`
  function() {
    console.error = globalThis.__helpOriginalError;
    delete globalThis.__helpOriginalError;
  }
`)

suite("Help", () => {
  test("usage documents the version flag", () => {
    captureConsoleLog()
    Help.printUsage()
    let logs: array<string> = %raw("globalThis.__helpLogs")
    assert_true(Array.some(logs, line => String.includes(line, "--version, -v")))
    restoreConsoleLog()
  })

  test("unknown help command is written to stderr", () => {
    captureConsoleError()
    Help.printHelpFor("missing")
    let errors: array<string> = %raw("globalThis.__helpErrors")
    assert_eq(Array.get(errors, 0), Some("Unknown command: missing"))
    restoreConsoleError()
  })
})
