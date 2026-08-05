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

type cliResult = {
  code: int,
  stdout: string,
  stderr: string,
  skipped: bool,
}

external runNodeAs: array<string> => promise<cliResult> = "%identity"

let runCliNodeTyped = args => runNodeAs(runCliNode(args))

suite("CLI Integration", () => {
  testAsync("empty args prints usage", resolve => {
    runCliNodeTyped([])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint <command>"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("missing generate classification prints error", resolve => {
    runCliNodeTyped(["generate"])->Promise.then(nodeRes => {
      assert_true(nodeRes.code != 0)
      assert_true(String.includes(nodeRes.stderr, "Error: 'generate' requires a classification"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("help generate prints detailed subcommand help", resolve => {
    runCliNodeTyped(["help", "generate"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint generate <class>"))
      assert_true(String.includes(nodeRes.stdout, "Template classification name"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("generate --help prints generate usage", resolve => {
    runCliNodeTyped(["generate", "--help"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint generate <class>"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("template --help prints template usage", resolve => {
    runCliNodeTyped(["template", "--help"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint template <action> [name]"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("generator --help prints generator usage", resolve => {
    runCliNodeTyped(["generator", "--help"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint generator <action> <name>"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("help generator prints detailed generator help", resolve => {
    runCliNodeTyped(["help", "generator"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint generator <action> <name>"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("help help prints global usage", resolve => {
    runCliNodeTyped(["help", "help"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "Usage: blueprint <command> [options]"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("help usage lists probe commands", resolve => {
    runCliNodeTyped(["help"])->Promise.then(nodeRes => {
      assert_eq(nodeRes.code, 0)
      assert_true(String.includes(nodeRes.stdout, "healthz"))
      assert_true(String.includes(nodeRes.stdout, "readyz"))
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("healthz and readyz print probe status", resolve => {
    runCliNodeTyped(["healthz"])->Promise.then(nodeHealth => {
      assert_eq(nodeHealth.code, 0)
      assert_true(String.includes(nodeHealth.stdout, "\"status\":\"ok\""))
      runCliNodeTyped(["readyz"])->Promise.then(nodeReady => {
        assert_eq(nodeReady.code, 0)
        assert_true(String.includes(nodeReady.stdout, "\"status\":\"not_ready\""))
        resolve()
        Promise.resolve()
      })
    })->ignore
  })

  testAsync("generate unknown classification prints error", resolve => {
    runCliNodeTyped(["generate", "unknown_test_class"])->Promise.then(nodeRes => {
      assert_true(String.includes(nodeRes.stderr, "generator not found") || String.includes(nodeRes.stdout, "generator not found"))
      resolve()
      Promise.resolve()
    })->ignore
  })
})