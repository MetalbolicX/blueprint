open TestHelpers

let setupMock: unit => unit = %raw(`
  function() {
    globalThis.Deno = {
      Command: class {
        constructor(cmd, options) {
          this.cmd = cmd;
          this.options = options;
        }
        async output() {
          if (this.options.args[1].includes('deno-test')) {
            const encoder = new TextEncoder();
            return {
              code: 0,
              stdout: encoder.encode("deno-test\\n"),
              stderr: encoder.encode(""),
              signal: null
            };
          }
          return {
            code: 1,
            stdout: new Uint8Array(0),
            stderr: new Uint8Array(0),
            signal: null
          };
        }
      }
    };
  }
`)

let teardownMock: unit => unit = %raw(`
  function() {
    delete globalThis.Deno;
  }
`)

suite("DenoShell adapter", () => {
  let shell = DenoShell.make()
  
  testAsync("execShellCommand runs via Deno.Command", resolve => {
    setupMock()
    shell.execShellCommand(~command="echo 'deno-test'")->Promise.then(res => {
      switch res {
      | Ok(out) => assert_true(String.includes(out, "deno-test"))
      | Error(_e) => assert_true(false) // Should not error with mock
      }
      teardownMock()
      resolve()
      Promise.resolve()
    })->ignore
  })
  
  testAsync("execAsync runs via Deno.Command", resolve => {
    setupMock()
    shell.execAsync("echo 'deno-test'")->Promise.then(res => {
      assert_eq(res.status, Some(0))
      assert_true(String.includes(res.stdout, "deno-test"))
      teardownMock()
      resolve()
      Promise.resolve()
    })->ignore
  })
})
