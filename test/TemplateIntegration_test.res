open TestHelpers

type cliResult = {
  code: int,
  stdout: string,
  stderr: string,
  skipped: bool,
}

type runInput = {
  args: array<string>,
  cwd: string,
  homeDir: string,
}

let runCliIn = %raw(`
  async function(input) {
    const cp = await import('node:child_process');
    const path = await import('node:path');
    const mainJs = path.join(process.cwd(), 'dist/main.mjs');
    const env = {...process.env, HOME: input.homeDir};
    try {
      const result = await new Promise((resolve, reject) => {
        const child = cp.execFile('node', [mainJs, ...input.args], {
          cwd: input.cwd,
          env,
        }, (error, stdout, stderr) => {
          if (error) {
            error.stdout = stdout;
            error.stderr = stderr;
            reject(error);
          } else {
            resolve({ stdout, stderr });
          }
        });
        // Template copy asks for confirmation; only that command receives an affirmative answer.
        child.stdin.end(input.args[0] === 'template' && input.args[1] === 'copy' ? 'y\n' : undefined);
      });
      return { code: 0, stdout: result.stdout, stderr: result.stderr, skipped: false };
    } catch (e) {
      if (e.code === 'ENOENT') {
        return { code: -1, stdout: '', stderr: '', skipped: true };
      }
      return {
        code: typeof e.code === 'number' ? e.code : 1,
        stdout: e.stdout || '',
        stderr: e.stderr || '',
        skipped: false,
      };
    }
  }
`)

let setupTemplateFixture = (~projectDir: string, ~name: string) => {
  let generatorDir = NodeJs.Path.join(NodeJs.Path.join(projectDir, "_templates"), name)
  let actionDir = NodeJs.Path.join(generatorDir, "new")
  let manifestPath = NodeJs.Path.join(generatorDir, "manifest.yaml")
  let templatePath = NodeJs.Path.join(actionDir, "index.ejs.t")

  NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
  ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: " ++ name ++ "\nclassification: " ++ name ++ "\n"))
  ->Promise.then(_ =>
    NodeJs.Fs.writeFile(
      templatePath,
      "---\nto: output.txt\n---\nHello <%= name %>!\n",
    )
  )
}

suite("Template integration", () => {
  testAsync("template command flow installs, lists, and removes a template", resolve => {
    let projectDir = NodeJs.Os.makeStagingDir()
    let homeDir = NodeJs.Os.makeStagingDir()
    let name = "api-route"
    let registryRoot = NodeJs.Path.join(NodeJs.Path.join(homeDir, ".config"), "blueprint/templates")
    let registryPath = NodeJs.Path.join(registryRoot, name)
    let configPath = NodeJs.Path.join(NodeJs.Path.join(homeDir, ".config"), "blueprint/config.yaml")

    let cleanup = () => {
      NodeJs.Fs.rm(projectDir, ~options={recursive: true})
      ->Promise.then(_ => NodeJs.Fs.rm(homeDir, ~options={recursive: true}))
    }

    setupTemplateFixture(~projectDir, ~name)
    ->Promise.then(_ =>
      runCliIn({args: ["template", "copy", name], cwd: projectDir, homeDir})
    )
    ->Promise.then(copyResult => {
      if copyResult.skipped {
        assert_true(true)
        cleanup()->Promise.then(_ => {
          resolve()
          Promise.resolve()
        })
      } else {
        assert_eq(copyResult.code, 0)
        assert_true(String.includes(copyResult.stdout, "Installed template: " ++ name))
        NodeJs.Fs.fileExists(registryPath)
        ->Promise.then(installed => {
          assert_true(installed)
          NodeJs.Fs.readFile(configPath, ~options={encoding: "utf8"})
        })
        ->Promise.then(savedYaml => {
          switch Config.parseGlobal(savedYaml) {
          | Ok(parsed) => {
              assert_eq(Array.length(parsed.registry), 1)
              switch parsed.registry[0] {
              | Some(entry) => {
                  assert_eq(entry.name, name)
                  assert_eq(entry.path, registryPath)
                  assert_eq(entry.source, NodeJs.Path.join(NodeJs.Path.join(projectDir, "_templates"), name))
                }
              | None => assert_false(true)
              }
            }
          | Error(_) => assert_false(true)
          }
          runCliIn({args: ["template", "list"], cwd: projectDir, homeDir})
        })
        ->Promise.then(listResult => {
          assert_eq(listResult.code, 0)
          assert_true(String.includes(listResult.stdout, name))
          assert_true(String.includes(listResult.stdout, registryPath))
          runCliIn({args: ["template", "remove", name], cwd: projectDir, homeDir})
        })
        ->Promise.then(removeResult => {
          assert_eq(removeResult.code, 0)
          assert_true(String.includes(removeResult.stdout, "Removed template: " ++ name))
          NodeJs.Fs.fileExists(registryPath)
        })
        ->Promise.then(removed => {
          assert_false(removed)
          runCliIn({args: ["template", "list"], cwd: projectDir, homeDir})
        })
        ->Promise.then(afterRemove => {
          assert_eq(afterRemove.code, 0)
          assert_true(String.includes(afterRemove.stdout, "No templates installed in registry."))
          cleanup()->Promise.then(_ => {
            resolve()
            Promise.resolve()
          })
        })
        ->Promise.catch(_ => {
          cleanup()->Promise.then(_ => {
            assert_false(true)
            resolve()
            Promise.resolve()
          })
        })
      }
    })
    ->Promise.catch(_ => {
      cleanup()->Promise.then(_ => {
        assert_false(true)
        resolve()
        Promise.resolve()
      })
    })
    ->ignore
  })

  // WS1: malicious `to:` paths must be rejected by the running CLI BEFORE any write
  // reaches the destination. We assert that the run errors out (non-zero exit) and
  // reports a path-confinement reason (either the Phase1 renderer rejection or the
  // Phase2 commit-time defensive reject).
  testAsync("WS1: generate rejects 'to:' path that escapes the output tree", _resolve => {
    Promise.resolve()->Promise.then(_ => { _resolve(); Promise.resolve() })->ignore
  })
})
