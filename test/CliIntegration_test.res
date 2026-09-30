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

type lifecycleResult = {
  initCode: int,
  eofCode: int,
  pipedCode: int,
  eofOutput: string,
  pipedOutput: string,
}

let runLifecycleChecks = %raw(`
  async function() {
    const [{default: fs}, {default: os}, {default: path}, {spawnSync}] = await Promise.all([
      import('node:fs'), import('node:os'), import('node:path'), import('node:child_process')
    ]);
    const binary = path.resolve('dist/main.mjs');
    const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'blueprint-eof-'));
    const run = (args, input = '') => spawnSync(process.execPath, [binary, ...args], {
      cwd, input, encoding: 'utf8', timeout: 5000
    });
    try {
      const init = run(['init']);
      fs.mkdirSync(path.join(cwd, '_templates', 'demo'), {recursive: true});
      fs.writeFileSync(path.join(cwd, '_templates', 'demo', 'manifest.yaml'), 'name: demo\nclassification: demo\n');
      const eof = run(['generator', 'add-file', 'demo']);
      const piped = run(['generator', 'add-file', 'demo'], 'new\nindex.ejs.t\nhello.txt\n\n\n');
      return {
        initCode: init.status ?? -1,
        eofCode: eof.status ?? -1,
        pipedCode: piped.status ?? -1,
        eofOutput: (eof.stderr || '') + (eof.stdout || ''),
        pipedOutput: (piped.stderr || '') + (piped.stdout || ''),
      };
    } finally {
      fs.rmSync(cwd, {recursive: true, force: true});
    }
  }
`)

external runLifecycleChecksTyped: unit => promise<lifecycleResult> = "%identity"

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

  testAsync("healthz and readyz report status before generate initialization", resolve => {
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

  testAsync("stdin EOF exits cleanly while piped prompt answers remain supported", resolve => {
    runLifecycleChecksTyped(runLifecycleChecks())->Promise.then(result => {
      assert_eq(result.initCode, 0)
      assert_eq(result.eofCode, 1)
      assert_true(String.includes(result.eofOutput, "input ended before an answer was provided"))
      assert_true(String.includes(result.eofOutput, "use --force"))
      assert_eq(result.pipedCode, 0)
      assert_true(String.includes(result.pipedOutput, "Created template:"))
      resolve()
      Promise.resolve()
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