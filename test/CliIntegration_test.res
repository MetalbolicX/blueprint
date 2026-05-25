open TestHelpers

let runCliNode = %raw(`
  async function(args) {
    const cp = await import('node:child_process');
    const util = await import('node:util');
    const execFile = util.promisify(cp.execFile);
    try {
      const { stdout, stderr } = await execFile('node', ['dist/main.mjs', ...args]);
      return { code: 0, stdout, stderr, skipped: false };
    } catch (e) {
      return { code: e.code || 1, stdout: e.stdout || '', stderr: e.stderr || '', skipped: false };
    }
  }
`)

let runCliDeno = %raw(`
  async function(args) {
    const cp = await import('node:child_process');
    const util = await import('node:util');
    const execFile = util.promisify(cp.execFile);
    try {
      // Setup Deno mock for Windows/Node environments without actual Deno installed, or just run Deno
      // If we don't have Deno installed, we might get ENOENT.
      const { stdout, stderr } = await execFile('deno', ['run', '-A', 'dist/main.mjs', ...args]);
      return { code: 0, stdout, stderr, skipped: false };
    } catch (e) {
      // If deno is missing, just skip the test or mock it.
      if (e.code === 'ENOENT') {
        return { code: -1, stdout: '', stderr: '', skipped: true };
      }
      return { code: e.code || 1, stdout: e.stdout || '', stderr: e.stderr || '', skipped: false };
    }
  }
`)

type cliResult = {
  code: int,
  stdout: string,
  stderr: string,
  skipped: bool,
}

external runNodeAs: array<string> => promise<cliResult> = "%identity"
external runDenoAs: array<string> => promise<cliResult> = "%identity"

let runCliNodeTyped = args => runNodeAs(runCliNode(args))
let runCliDenoTyped = args => runDenoAs(runCliDeno(args))

suite("CLI Integration Parity", () => {
  testAsync("empty args prints usage across runtimes", resolve => {
    runCliNodeTyped([])->Promise.then(nodeRes => {
      runCliDenoTyped([])->Promise.then(denoRes => {
        let nCode = nodeRes.code
        let nStdout = nodeRes.stdout
        
        let dSkipped = denoRes.skipped
        if dSkipped {
          // Skip deno check if Deno is not installed in the test environment
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint <command>"))
        } else {
          let dCode = denoRes.code
          let dStdout = denoRes.stdout
          
          assert_eq(nCode, dCode)
          assert_true(String.includes(nStdout, "Usage: blueprint <command>"))
          assert_true(String.includes(dStdout, "Usage: blueprint <command>"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("missing generate classification prints error across runtimes", resolve => {
    runCliNodeTyped(["generate"])->Promise.then(nodeRes => {
      runCliDenoTyped(["generate"])->Promise.then(denoRes => {
        let nCode = nodeRes.code
        let nStderr = nodeRes.stderr
        
        let dSkipped = denoRes.skipped
        if dSkipped {
          assert_true(nCode != 0)
          assert_true(String.includes(nStderr, "Error: 'generate' requires a classification"))
        } else {
          let dCode = denoRes.code
          let dStderr = denoRes.stderr
          
          assert_eq(nCode, dCode)
          assert_true(String.includes(nStderr, "Error: 'generate' requires a classification"))
          assert_true(String.includes(dStderr, "Error: 'generate' requires a classification"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("generate unknown classification prints error", resolve => {
    runCliNodeTyped(["generate", "unknown_test_class"])->Promise.then(nodeRes => {
      runCliDenoTyped(["generate", "unknown_test_class"])->Promise.then(denoRes => {
        let nStderr = nodeRes.stderr
        let nStdout = nodeRes.stdout
        
        let dSkipped = denoRes.skipped
        if dSkipped {
          assert_true(String.includes(nStderr, "generator not found") || String.includes(nStdout, "generator not found"))
        } else {
          let dStderr = denoRes.stderr
          let dStdout = denoRes.stdout
          
          assert_true(String.includes(nStderr, "generator not found") || String.includes(nStdout, "generator not found"))
          assert_true(String.includes(dStderr, "generator not found") || String.includes(dStdout, "generator not found"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })
})
