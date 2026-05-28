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
      if (e.code === 'ENOENT') {
        return { code: -1, stdout: '', stderr: '', skipped: true };
      }
      return { code: typeof e.code === 'number' ? e.code : 1, stdout: e.stdout || '', stderr: e.stderr || '', skipped: false };
    }
  }
`)

let runCliDeno = %raw(`
  async function(args) {
    const cp = await import('node:child_process');
    const util = await import('node:util');
    const execFile = util.promisify(cp.execFile);
    try {
      const { stdout, stderr } = await execFile('deno', ['run', '-A', 'dist/main.mjs', ...args]);
      return { code: 0, stdout, stderr, skipped: false };
    } catch (e) {
      if (e.code === 'ENOENT') {
        return { code: -1, stdout: '', stderr: '', skipped: true };
      }
      return { code: typeof e.code === 'number' ? e.code : 1, stdout: e.stdout || '', stderr: e.stderr || '', skipped: false };
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

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint <command>"))
        } else {
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStdout, "Usage: blueprint <command>"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint <command>"))
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

        if denoRes.skipped {
          assert_true(nCode != 0)
          assert_true(String.includes(nStderr, "Error: 'generate' requires a classification"))
        } else {
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStderr, "Error: 'generate' requires a classification"))
          assert_true(String.includes(denoRes.stderr, "Error: 'generate' requires a classification"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("help generate prints detailed subcommand help", resolve => {
    runCliNodeTyped(["help", "generate"])->Promise.then(nodeRes => {
      runCliDenoTyped(["help", "generate"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint generate <class>"))
          assert_true(String.includes(nStdout, "Template classification name"))
        } else {
          assert_eq(nCode, denoRes.code)
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint generate <class>"))
          assert_true(String.includes(nStdout, "Template classification name"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint generate <class>"))
          assert_true(String.includes(denoRes.stdout, "Template classification name"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("generate --help prints generate usage", resolve => {
    runCliNodeTyped(["generate", "--help"])->Promise.then(nodeRes => {
      runCliDenoTyped(["generate", "--help"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint generate <class>"))
        } else {
          assert_eq(nCode, 0)
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStdout, "Usage: blueprint generate <class>"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint generate <class>"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("template --help prints template usage", resolve => {
    runCliNodeTyped(["template", "--help"])->Promise.then(nodeRes => {
      runCliDenoTyped(["template", "--help"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint template <action> [name]"))
        } else {
          assert_eq(nCode, 0)
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStdout, "Usage: blueprint template <action> [name]"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint template <action> [name]"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("generator --help prints generator usage", resolve => {
    runCliNodeTyped(["generator", "--help"])->Promise.then(nodeRes => {
      runCliDenoTyped(["generator", "--help"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint generator <action> <name>"))
        } else {
          assert_eq(nCode, 0)
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStdout, "Usage: blueprint generator <action> <name>"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint generator <action> <name>"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("help generator prints detailed generator help", resolve => {
    runCliNodeTyped(["help", "generator"])->Promise.then(nodeRes => {
      runCliDenoTyped(["help", "generator"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint generator <action> <name>"))
        } else {
          assert_eq(nCode, denoRes.code)
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint generator <action> <name>"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint generator <action> <name>"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("help help prints global usage", resolve => {
    runCliNodeTyped(["help", "help"])->Promise.then(nodeRes => {
      runCliDenoTyped(["help", "help"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "Usage: blueprint <command> [options]"))
        } else {
          assert_eq(nCode, 0)
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStdout, "Usage: blueprint <command> [options]"))
          assert_true(String.includes(denoRes.stdout, "Usage: blueprint <command> [options]"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("help usage lists probe commands", resolve => {
    runCliNodeTyped(["help"])->Promise.then(nodeRes => {
      runCliDenoTyped(["help"])->Promise.then(denoRes => {
        let nStdout = nodeRes.stdout
        let nCode = nodeRes.code

        if denoRes.skipped {
          assert_eq(nCode, 0)
          assert_true(String.includes(nStdout, "healthz"))
          assert_true(String.includes(nStdout, "readyz"))
        } else {
          assert_eq(nCode, 0)
          assert_eq(nCode, denoRes.code)
          assert_true(String.includes(nStdout, "healthz"))
          assert_true(String.includes(nStdout, "readyz"))
          assert_true(String.includes(denoRes.stdout, "healthz"))
          assert_true(String.includes(denoRes.stdout, "readyz"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("healthz and readyz print probe status across runtimes", resolve => {
    runCliNodeTyped(["healthz"])->Promise.then(nodeHealth => {
      runCliDenoTyped(["healthz"])->Promise.then(denoHealth => {
        let nHealthStdout = nodeHealth.stdout
        let nHealthCode = nodeHealth.code

        if denoHealth.skipped {
          assert_eq(nHealthCode, 0)
          assert_true(String.includes(nHealthStdout, "\"status\":\"ok\""))
        } else {
          assert_eq(nHealthCode, 0)
          assert_eq(nHealthCode, denoHealth.code)
          assert_true(String.includes(nHealthStdout, "\"status\":\"ok\""))
          assert_true(String.includes(denoHealth.stdout, "\"status\":\"ok\""))
        }

        runCliNodeTyped(["readyz"])->Promise.then(nodeReady => {
          runCliDenoTyped(["readyz"])->Promise.then(denoReady => {
            let nReadyStdout = nodeReady.stdout
            let nReadyCode = nodeReady.code

            if denoReady.skipped {
              assert_eq(nReadyCode, 0)
              assert_true(String.includes(nReadyStdout, "\"status\":\"not_ready\""))
            } else {
              assert_eq(nReadyCode, 0)
              assert_eq(nReadyCode, denoReady.code)
              assert_true(String.includes(nReadyStdout, "\"status\":\"not_ready\""))
              assert_true(String.includes(denoReady.stdout, "\"status\":\"not_ready\""))
            }
            resolve()
            Promise.resolve()
          })
        })->ignore
      })
    })->ignore
  })

  testAsync("generate unknown classification prints error", resolve => {
    runCliNodeTyped(["generate", "unknown_test_class"])->Promise.then(nodeRes => {
      runCliDenoTyped(["generate", "unknown_test_class"])->Promise.then(denoRes => {
        let nStderr = nodeRes.stderr
        let nStdout = nodeRes.stdout

        if denoRes.skipped {
          assert_true(String.includes(nStderr, "generator not found") || String.includes(nStdout, "generator not found"))
        } else {
          assert_true(String.includes(nStderr, "generator not found") || String.includes(nStdout, "generator not found"))
          assert_true(String.includes(denoRes.stderr, "generator not found") || String.includes(denoRes.stdout, "generator not found"))
        }
        resolve()
        Promise.resolve()
      })
    })->ignore
  })
})
