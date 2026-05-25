open TestHelpers

let runCliNode = %raw(`
  async function(args) {
    const cp = await import('node:child_process');
    const util = await import('node:util');
    const execFile = util.promisify(cp.execFile);
    try {
      const { stdout, stderr } = await execFile('node', ['dist/main.mjs', ...args]);
      return { code: 0, stdout, stderr };
    } catch (e) {
      return { code: e.code || 1, stdout: e.stdout || '', stderr: e.stderr || '' };
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
      return { code: 0, stdout, stderr };
    } catch (e) {
      // If deno is missing, just skip the test or mock it.
      if (e.code === 'ENOENT') {
        return { code: -1, skipped: true };
      }
      return { code: e.code || 1, stdout: e.stdout || '', stderr: e.stderr || '' };
    }
  }
`)

suite("CLI Integration Parity", () => {
  testAsync("empty args prints usage across runtimes", resolve => {
    runCliNode([])->Promise.then(_nodeRes => {
      runCliDeno([])->Promise.then(_denoRes => {
        let nCode: int = %raw(`nodeRes.code`)
        let nStdout: string = %raw(`nodeRes.stdout`)
        
        let dSkipped: bool = %raw(`!!denoRes.skipped`)
        if dSkipped {
          // Skip deno check if Deno is not installed in the test environment
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint <command>"))
        } else {
          let dCode: int = %raw(`denoRes.code`)
          let dStdout: string = %raw(`denoRes.stdout`)
          
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
    runCliNode(["generate"])->Promise.then(_nodeRes => {
      runCliDeno(["generate"])->Promise.then(_denoRes => {
        let nCode: int = %raw(`nodeRes.code`)
        let nStderr: string = %raw(`nodeRes.stderr`)
        
        let dSkipped: bool = %raw(`!!denoRes.skipped`)
        if dSkipped {
          assert_eq(nCode, 1)
          assert_true(String.includes(nStderr, "Error: 'generate' requires a classification"))
        } else {
          let dCode: int = %raw(`denoRes.code`)
          let dStderr: string = %raw(`denoRes.stderr`)
          
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
    runCliNode(["generate", "unknown_test_class"])->Promise.then(_nodeRes => {
      runCliDeno(["generate", "unknown_test_class"])->Promise.then(_denoRes => {
        let nStderr: string = %raw(`nodeRes.stderr`)
        let nStdout: string = %raw(`nodeRes.stdout`)
        
        let dSkipped: bool = %raw(`!!denoRes.skipped`)
        if dSkipped {
          assert_true(String.includes(nStderr, "generator not found") || String.includes(nStdout, "generator not found"))
        } else {
          let dStderr: string = %raw(`denoRes.stderr`)
          let dStdout: string = %raw(`denoRes.stdout`)
          
          assert_true(String.includes(nStderr, "generator not found") || String.includes(nStdout, "generator not found"))
          assert_true(String.includes(dStderr, "generator not found") || String.includes(dStdout, "generator not found"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })
})
