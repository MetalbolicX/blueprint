// SmokeIntegration_test — end-to-end CLI smoke tests
// Runs the actual blueprint CLI binary with real generator structures
// Validates the full pipeline: discovery → rendering → file output

open TestHelpers

type cliResult = {
  code: int,
  stdout: string,
  stderr: string,
  skipped: bool,
}

// Run the blueprint CLI as a subprocess in a specified cwd
// Uses absolute path to dist/main.mjs from the project root
let runCliIn: (array<string>, string) => promise<cliResult> = %raw(`
  async function(args, cwd) {
    const cp = await import('node:child_process');
    const path = await import('node:path');
    const util = await import('node:util');
    const execFile = util.promisify(cp.execFile);
    const mainJs = path.join(process.cwd(), 'dist/main.mjs');
    try {
      const { stdout, stderr } = await execFile('node', [mainJs, ...args], { cwd });
      return { code: 0, stdout, stderr, skipped: false };
    } catch (e) {
      if (e.code === 'ENOENT') {
        return { code: -1, stdout: '', stderr: '', skipped: true };
      }
      const out = e.stdout || '';
      const err = e.stderr || '';
      return { code: typeof e.code === 'number' ? e.code : 1, stdout: out, stderr: err, skipped: false };
    }
  }
`)

let setupGenerator = (~baseDir, ~generatorName="my-component") => {
  let templatesDir = NodeJs.Path.join(baseDir, "_templates")
  let genDir = NodeJs.Path.join(templatesDir, generatorName)
  let actionDir = NodeJs.Path.join(genDir, "new")
  let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
  let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

  NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
  ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: " ++ generatorName ++ "\nclassification: " ++ generatorName ++ "\n"))
  ->Promise.then(_ =>
    NodeJs.Fs.writeFile(
      templatePath,
      "---\nto: output.txt\n---\nHello <%= name %>!\n",
    )
  )
}

suite("Smoke Integration", () => {
  testAsync("generate: creates output file from real generator", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")

    setupGenerator(~baseDir=tmpDir)
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--name", "World", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        assert_true(String.includes(result.stdout, "1 file(s)"))
        let outputFile = NodeJs.Path.join(outputDir, "output.txt")
        NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_eq(String.trim(content), "Hello World!")
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: force=true overwrites existing output file", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")
    let outputFile = NodeJs.Path.join(outputDir, "output.txt")

    setupGenerator(~baseDir=tmpDir)
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(outputFile, "old-content"))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--name", "World", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        assert_true(String.includes(result.stdout, "1 file(s)"))
        NodeJs.Fs.readFile(outputFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_eq(String.trim(content), "Hello World!")
          assert_false(String.includes(content, "old-content"))
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: unknown classification prints error", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()

    setupGenerator(~baseDir=tmpDir)
    ->Promise.then(_ =>
      runCliIn(["generate", "does-not-exist"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
      } else {
        assert_true(result.code != 0)
        assert_true(String.includes(result.stderr, "generator not found") || String.includes(result.stderr, "not found"))
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: inject directive replaces matched content in existing file", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")
    let targetFile = NodeJs.Path.join(outputDir, "output.js")

    // Create generator with inject template
    let templatesDir = NodeJs.Path.join(tmpDir, "_templates")
    let genDir = NodeJs.Path.join(templatesDir, "my-component")
    let actionDir = NodeJs.Path.join(genDir, "new")
    let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: my-component\nclassification: my-component\n"))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        templatePath,
        "---\nto: output.js\ninject: const old =\nforce: true\n---\nconst newValue = 1;\n",
      )
    )
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "const old = 'original';\n"))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        NodeJs.Fs.readFile(targetFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_true(String.includes(content, "const newValue"))
          assert_false(String.includes(content, "const old = 'original'"))
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: inject directive fails when target file does not exist", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")

    let templatesDir = NodeJs.Path.join(tmpDir, "_templates")
    let genDir = NodeJs.Path.join(templatesDir, "my-component")
    let actionDir = NodeJs.Path.join(genDir, "new")
    let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: my-component\nclassification: my-component\n"))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        templatePath,
        "---\nto: output.js\ninject: const old =\nforce: true\n---\nconst newValue = 1;\n",
      )
    )
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
      } else {
        assert_true(result.code != 0)
        assert_true(
          String.includes(result.stderr, "not found") ||
          String.includes(result.stderr, "does not exist") ||
          String.includes(result.stderr, "output.js"),
        )
      }
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: before directive inserts content before matched line", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")
    let targetFile = NodeJs.Path.join(outputDir, "output.js")

    let templatesDir = NodeJs.Path.join(tmpDir, "_templates")
    let genDir = NodeJs.Path.join(templatesDir, "my-component")
    let actionDir = NodeJs.Path.join(genDir, "new")
    let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: my-component\nclassification: my-component\n"))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        templatePath,
        "---\nto: output.js\nbefore: module.exports\nforce: true\n---\nconst myImport = require('helper');\n",
      )
    )
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "module.exports = { value: 1 };\n"))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        NodeJs.Fs.readFile(targetFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_true(String.includes(content, "const myImport"))
          assert_true(String.includes(content, "module.exports"))
          // myImport should appear before module.exports
          let importIdx = String.indexOf(content, "const myImport")
          let exportIdx = String.indexOf(content, "module.exports")
          assert_true(importIdx < exportIdx)
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: after directive inserts content after matched line", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")
    let targetFile = NodeJs.Path.join(outputDir, "output.js")

    let templatesDir = NodeJs.Path.join(tmpDir, "_templates")
    let genDir = NodeJs.Path.join(templatesDir, "my-component")
    let actionDir = NodeJs.Path.join(genDir, "new")
    let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: my-component\nclassification: my-component\n"))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        templatePath,
        "---\nto: output.js\nafter: const start\nforce: true\n---\nconst inserted = 1;\n",
      )
    )
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "const start = true;\nconst other = 2;\n"))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        NodeJs.Fs.readFile(targetFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_true(String.includes(content, "const inserted"))
          assert_true(String.includes(content, "const start = true"))
          assert_true(String.includes(content, "const other = 2"))
          // inserted should appear after "const start"
          let startIdx = String.indexOf(content, "const start")
          let insertedIdx = String.indexOf(content, "const inserted")
          assert_true(startIdx < insertedIdx)
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: prepend directive adds content to start of file", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")
    let targetFile = NodeJs.Path.join(outputDir, "output.js")

    let templatesDir = NodeJs.Path.join(tmpDir, "_templates")
    let genDir = NodeJs.Path.join(templatesDir, "my-component")
    let actionDir = NodeJs.Path.join(genDir, "new")
    let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: my-component\nclassification: my-component\n"))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        templatePath,
        "---\nto: output.js\nprepend: true\nforce: true\n---\n// Prepended header\n",
      )
    )
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "const existing = 1;\n"))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        NodeJs.Fs.readFile(targetFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_true(String.startsWith(content, "// Prepended header"))
          assert_true(String.includes(content, "const existing"))
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("generate: append directive adds content to end of file", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let outputDir = NodeJs.Path.join(tmpDir, "my-output")
    let targetFile = NodeJs.Path.join(outputDir, "output.js")

    let templatesDir = NodeJs.Path.join(tmpDir, "_templates")
    let genDir = NodeJs.Path.join(templatesDir, "my-component")
    let actionDir = NodeJs.Path.join(genDir, "new")
    let manifestPath = NodeJs.Path.join(genDir, "manifest.yaml")
    let templatePath = NodeJs.Path.join(actionDir, "hello.ejs.t")

    NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(manifestPath, "name: my-component\nclassification: my-component\n"))
    ->Promise.then(_ =>
      NodeJs.Fs.writeFile(
        templatePath,
        "---\nto: output.js\nappend: true\nforce: true\n---\n// Appended footer\n",
      )
    )
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(targetFile, "const existing = 1;\n"))
    ->Promise.then(_ =>
      runCliIn(["generate", "my-component", "--output", outputDir, "--force"], tmpDir)
    )
    ->Promise.then(result => {
      if result.skipped {
        assert_true(true)
        NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
        resolve()
        Promise.resolve()
      } else {
        assert_eq(result.code, 0)
        NodeJs.Fs.readFile(targetFile, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          assert_true(String.includes(content, "const existing"))
          assert_true(String.includes(content, "// Appended footer"))
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          resolve()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
          assert_false(true)
          resolve()
          Promise.resolve()
        })
      }
    })
    ->Promise.catch(_ => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      assert_false(true)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
