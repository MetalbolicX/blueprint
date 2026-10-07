open TestHelpers

let fsAdapter = NodeJsFileSystem.make()
let pathAdapter = NodeJsPath.make()

let makeInstallGuardFs = (~symlinkPath: string): (Ports.fileSystem, ref<int>, ref<int>, ref<int>) => {
  let base = NodeJsFileSystem.make()
  let cpCalls = ref(0)
  let writeCalls = ref(0)
  let rmCalls = ref(0)
  let source = "/source"
  let fs: Ports.fileSystem = {
    ...base,
    writeFile: (_path, _contents, ~options as _=?) => {
      writeCalls := writeCalls.contents + 1
      Promise.resolve()
    },
    rm: (_path, ~options as _=?) => {
      rmCalls := rmCalls.contents + 1
      Promise.resolve()
    },
    mkdir: (_path, ~options as _=?) => Promise.resolve(""),
    cp: (_src, _dst, ~options as _=?) => {
      cpCalls := cpCalls.contents + 1
      Promise.resolve()
    },
    readdir: (path, ~options as _=?) =>
      Promise.resolve(path == source ? (symlinkPath == "/source/.blueprint-provenance" ? [".blueprint-provenance", "templates"] : ["templates"]) : path == "/source/templates" ? ["x.ejs.t"] : []),
    stat: path => Promise.resolve({isDirectory: () => path == source || path == "/source/templates", isFile: () => true}: Ports.statResult),
    lstat: path => Promise.resolve({
      isDirectory: () => path == source || path == "/source/templates",
      isFile: () => true,
      isSymbolicLink: () => path == symlinkPath,
    }: Ports.lstatResult),
  }
  (fs, cpCalls, writeCalls, rmCalls)
}

let installGuardDeps = (~fs: Ports.fileSystem): Ports.deps => ({
    fs: fs,
    path: pathAdapter,
    process: NodeJsProcess.make(),
    shell: NodeJsShell.make(),
    argParser: NodeJsArgParser.make(),
    interactiveIO: NodeJsInteractiveIO.make(),
    yamlParser: NodeJsYamlParser.make(),
    ejs: NodeJsEjs.make(),
    fetcher: NodeJsFetcher.make(),
    pathSecurity: NodeJsPathSecurity.make(),
    shellBuilder: NodeJsShellBuilder.make(),
    envFilter: NodeJsEnvFilter.make(),
    hooks: TestPorts.stubHooks,
  })

let writeGeneratorFixture = (~root: string, ~name: string) => {
  let generatorDir = NodeJs.Path.join(root, name)
  let actionDir = NodeJs.Path.join(generatorDir, "new")
  NodeJs.Fs.mkdir(actionDir, ~options={recursive: true})
  ->Promise.then(_ =>
    NodeJs.Fs.writeFile(
      NodeJs.Path.join(generatorDir, "manifest.yaml"),
      "name: " ++ name ++ "\nclassification: " ++ name ++ "\nprompts: []\n",
    )
  )
  ->Promise.then(_ =>
    NodeJs.Fs.writeFile(
      NodeJs.Path.join(actionDir, "index.ts.ejs.t"),
      "---\nto: src/{{ .name }}.ts\n---\nexport const value = '{{ .name }}'\n",
    )
  )
}

suite("TemplateRegistry", () => {
  test("buildGenerateSearchPaths: keeps project-local precedence", () => {
    let testDeps: Ports.deps = {
      fs: fsAdapter,
      path: pathAdapter,
      process: NodeJsProcess.make(),
      shell: NodeJsShell.make(),
      argParser: NodeJsArgParser.make(),
      interactiveIO: NodeJsInteractiveIO.make(),
      yamlParser: NodeJsYamlParser.make(),
      ejs: NodeJsEjs.make(),
      fetcher: NodeJsFetcher.make(),
      pathSecurity: NodeJsPathSecurity.make(),
      shellBuilder: NodeJsShellBuilder.make(),
      envFilter: NodeJsEnvFilter.make(),
      hooks: TestPorts.stubHooks,
    }
    let paths = Cli.buildGenerateSearchPaths(
        ~deps=testDeps,
      ~projectPaths=["_templates", "templates"],
      ~registry=[
        {
          name: "service",
          source: "/workspace/_templates/service",
          path: "/home/user/.config/blueprint/templates/service",
        }: Config.templateSource,
      ],
      ~globalTemplates=["/opt/company/templates"],
    )
    let globalRoot = NodeJs.Path.join(NodeJs.Path.join(NodeJs.Path.join(testDeps.process.homedir(), ".config"), "blueprint"), "templates")

    assert_eq(paths[0], Some(NodeJs.Path.resolve(testDeps.process.cwd(), "_templates")))
    assert_eq(paths[1], Some(NodeJs.Path.resolve(testDeps.process.cwd(), "templates")))
    assert_eq(paths[2], Some("/home/user/.config/blueprint/templates"))
    assert_eq(paths[3], Some("/opt/company/templates"))
    assert_eq(paths[4], Some(globalRoot))
  })

  testAsync("copyTemplateToRegistry: copies full generator and persists metadata", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let sourceRoot = NodeJs.Path.join(tmpDir, "source")
    let registryRoot = NodeJs.Path.join(tmpDir, "registry")
    let configPath = NodeJs.Path.join(tmpDir, "config.yaml")
    let name = "model"

    let cfg: Config.globalConfig = {
      templates: [],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      registry: [],
    }

    NodeJs.Fs.mkdir(sourceRoot, ~options={recursive: true})
    ->Promise.then(_ => writeGeneratorFixture(~root=sourceRoot, ~name))
    ->Promise.then(_ => {
      Cli.copyTemplateToRegistry(
        ~deps={
          fs: fsAdapter,
          path: pathAdapter,
          process: NodeJsProcess.make(),
          shell: NodeJsShell.make(),
          argParser: NodeJsArgParser.make(),
          interactiveIO: NodeJsInteractiveIO.make(),
          yamlParser: NodeJsYamlParser.make(),
          ejs: NodeJsEjs.make(),
          fetcher: NodeJsFetcher.make(),
          pathSecurity: NodeJsPathSecurity.make(),
          shellBuilder: NodeJsShellBuilder.make(),
          envFilter: NodeJsEnvFilter.make(),
          hooks: TestPorts.stubHooks,
        },
        ~fs=fsAdapter,
        ~path=pathAdapter,
        ~name,
        ~sourcePath=NodeJs.Path.join(sourceRoot, name),
        ~registryRoot,
        ~configPath,
        ~globalConfig=cfg,
        ~force=true,
        ~confirmOverwrite=_ => Promise.resolve(false),
      )
    })
    ->Promise.then(result => {
      switch result {
      | Error(_) => {
          assert_false(true)
          Promise.resolve()
        }
      | Ok(updated) => {
          let installedGeneratorDir = NodeJs.Path.join(registryRoot, name)
          let copiedManifest = NodeJs.Path.join(installedGeneratorDir, "manifest.yaml")
          let copiedTemplate = NodeJs.Path.join(installedGeneratorDir, "new/index.ts.ejs.t")
          NodeJs.Fs.fileExists(copiedManifest)
          ->Promise.then(manifestExists => {
            assert_true(manifestExists)
            NodeJs.Fs.fileExists(copiedTemplate)
          })
          ->Promise.then(templateExists => {
            assert_true(templateExists)
            NodeJs.Fs.readFile(NodeJs.Path.join(installedGeneratorDir, ".blueprint-provenance"), ~options={encoding: "utf8"})
          })
          ->Promise.then(provenance => {
            assert_true(String.includes(provenance, NodeJs.Path.join(sourceRoot, name)))
            assert_eq(Array.length(updated.registry), 1)
            switch updated.registry[0] {
            | Some(entry) => {
                assert_eq(entry.path, installedGeneratorDir)
                assert_true(NodeJsPath.make().isAbsolute(entry.source))
              }
            | None => assert_false(true)
            }
            NodeJs.Fs.readFile(configPath, ~options={encoding: "utf8"})
          })
          ->Promise.then(savedYaml => {
            switch Config.parseGlobal(savedYaml) {
            | Ok(parsed) => {
                assert_eq(Array.length(parsed.registry), 1)
                resolve()
                Promise.resolve()
              }
            | Error(_) => {
                assert_false(true)
                resolve()
                Promise.resolve()
              }
            }
          })
        }
      }
    })
    ->ignore
  })

  testAsync("copyTemplateToRegistry: force skips overwrite prompt", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let sourceRoot = NodeJs.Path.join(tmpDir, "source")
    let registryRoot = NodeJs.Path.join(tmpDir, "registry")
    let configPath = NodeJs.Path.join(tmpDir, "config.yaml")
    let name = "service"
    let promptCalls = ref(0)

    let cfg: Config.globalConfig = {
      templates: [],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      registry: [{name, source: "/old/source", path: NodeJs.Path.join(registryRoot, name)}],
    }

    NodeJs.Fs.mkdir(sourceRoot, ~options={recursive: true})
    ->Promise.then(_ => writeGeneratorFixture(~root=sourceRoot, ~name))
    ->Promise.then(_ => NodeJs.Fs.mkdir(NodeJs.Path.join(registryRoot, name), ~options={recursive: true}))
    ->Promise.then(_ => NodeJs.Fs.writeFile(NodeJs.Path.join(NodeJs.Path.join(registryRoot, name), ".blueprint-provenance"), "source: untrusted copied marker\n"))
    ->Promise.then(_ => {
      Cli.copyTemplateToRegistry(
        ~deps={
          fs: fsAdapter,
          path: pathAdapter,
          process: NodeJsProcess.make(),
          shell: NodeJsShell.make(),
          argParser: NodeJsArgParser.make(),
          interactiveIO: NodeJsInteractiveIO.make(),
          yamlParser: NodeJsYamlParser.make(),
          ejs: NodeJsEjs.make(),
          fetcher: NodeJsFetcher.make(),
          pathSecurity: NodeJsPathSecurity.make(),
          shellBuilder: NodeJsShellBuilder.make(),
          envFilter: NodeJsEnvFilter.make(),
          hooks: TestPorts.stubHooks,
        },
        ~fs=fsAdapter,
        ~path=pathAdapter,
        ~name,
        ~sourcePath=NodeJs.Path.join(sourceRoot, name),
        ~registryRoot,
        ~configPath,
        ~globalConfig=cfg,
        ~force=true,
        ~confirmOverwrite=_ => {
          promptCalls := promptCalls.contents + 1
          Promise.resolve(true)
        },
      )
    })
    ->Promise.then(_ => {
      assert_eq(promptCalls.contents, 0)
      NodeJs.Fs.readFile(NodeJs.Path.join(NodeJs.Path.join(registryRoot, name), ".blueprint-provenance"), ~options={encoding: "utf8"})
    })
    ->Promise.then(marker => {
      assert_true(String.includes(marker, NodeJs.Path.join(sourceRoot, name)))
      assert_false(String.includes(marker, "untrusted copied marker"))
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("copyTemplateToRegistry: refuses symlinked provenance marker before mutation", resolve => {
    let (guardFs, cpCalls, writeCalls, rmCalls) = makeInstallGuardFs(~symlinkPath="/source/.blueprint-provenance")
    let deps = installGuardDeps(~fs=guardFs)
    Cli.copyTemplateToRegistry(
      ~deps,
      ~fs=guardFs,
      ~path=pathAdapter,
      ~name="guarded",
      ~sourcePath="/source",
      ~registryRoot="/registry",
      ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: []},
      ~force=true,
      ~confirmOverwrite=_ => Promise.resolve(false),
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Refusing to install /source: source already contains a .blueprint-provenance marker")
      | Ok(_) => assert_false(true)
      }
      assert_eq(cpCalls.contents, 0)
      assert_eq(writeCalls.contents, 0)
      assert_eq(rmCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("copyTemplateToRegistry: refuses other source symlinks before mutation", resolve => {
    let (guardFs, cpCalls, writeCalls, rmCalls) = makeInstallGuardFs(~symlinkPath="/source/templates/x.ejs.t")
    let deps = installGuardDeps(~fs=guardFs)
    Cli.copyTemplateToRegistry(
      ~deps,
      ~fs=guardFs,
      ~path=pathAdapter,
      ~name="guarded",
      ~sourcePath="/source",
      ~registryRoot="/registry",
      ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: []},
      ~force=true,
      ~confirmOverwrite=_ => Promise.resolve(false),
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Refusing to install /source: symbolic links are not allowed in templates")
      | Ok(_) => assert_false(true)
      }
      assert_eq(cpCalls.contents, 0)
      assert_eq(writeCalls.contents, 0)
      assert_eq(rmCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("copyTemplateToRegistry: refuses sources over the entry cap", resolve => {
    let base = NodeJsFileSystem.make()
    let names = Array.make(~length=10001, "entry")
    let cpCalls = ref(0)
    let fs: Ports.fileSystem = {
      ...base,
      readdir: (path, ~options as _=?) => Promise.resolve(path == "/source" ? names : []),
      stat: _ => Promise.resolve({isDirectory: () => true, isFile: () => false}: Ports.statResult),
      lstat: path => Promise.resolve({isDirectory: () => path == "/source", isFile: () => path != "/source", isSymbolicLink: () => false}: Ports.lstatResult),
      cp: (_src, _dst, ~options as _=?) => {
        cpCalls := cpCalls.contents + 1
        Promise.resolve()
      },
    }
    Cli.copyTemplateToRegistry(
      ~deps=installGuardDeps(~fs), ~fs, ~path=pathAdapter, ~name="guarded", ~sourcePath="/source",
      ~registryRoot="/registry", ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: []},
      ~force=true, ~confirmOverwrite=_ => Promise.resolve(false),
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Refusing to install /source: template tree exceeds entry cap (10000)")
      | Ok(_) => assert_false(true)
      }
      assert_eq(cpCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("copyTemplateToRegistry: refuses sources deeper than the depth cap", resolve => {
    let base = NodeJsFileSystem.make()
    let cpCalls = ref(0)
    let fs: Ports.fileSystem = {
      ...base,
      readdir: (_path, ~options as _=?) => Promise.resolve(["nested"]),
      stat: _ => Promise.resolve({isDirectory: () => true, isFile: () => false}: Ports.statResult),
      lstat: _ => Promise.resolve({isDirectory: () => true, isFile: () => false, isSymbolicLink: () => false}: Ports.lstatResult),
      cp: (_src, _dst, ~options as _=?) => {
        cpCalls := cpCalls.contents + 1
        Promise.resolve()
      },
    }
    Cli.copyTemplateToRegistry(
      ~deps=installGuardDeps(~fs), ~fs, ~path=pathAdapter, ~name="guarded", ~sourcePath="/source",
      ~registryRoot="/registry", ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: []},
      ~force=true, ~confirmOverwrite=_ => Promise.resolve(false),
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Refusing to install /source: template tree exceeds depth cap (32)")
      | Ok(_) => assert_false(true)
      }
      assert_eq(cpCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("copyTemplateToRegistry: validates before deleting an overwrite target", resolve => {
    let (base, cpCalls, writeCalls, rmCalls) = makeInstallGuardFs(~symlinkPath="/source/templates/x.ejs.t")
    let fs: Ports.fileSystem = {
      ...base,
      fileExists: _ => Promise.resolve(true),
    }
    let promptCalls = ref(0)
    Cli.copyTemplateToRegistry(
      ~deps=installGuardDeps(~fs), ~fs, ~path=pathAdapter, ~name="guarded", ~sourcePath="/source",
      ~registryRoot="/registry", ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: [{name: "guarded", source: "/old", path: "/registry/guarded"}]},
      ~force=false, ~confirmOverwrite=_ => {
        promptCalls := promptCalls.contents + 1
        Promise.resolve(true)
      },
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Refusing to install /source: symbolic links are not allowed in templates")
      | Ok(_) => assert_false(true)
      }
      assert_eq(promptCalls.contents, 0)
      assert_eq(cpCalls.contents, 0)
      assert_eq(writeCalls.contents, 0)
      assert_eq(rmCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("copyTemplateToRegistry: removes the target when copy leaves a provenance marker", resolve => {
    let (base, cpCalls, writeCalls, rmCalls) = makeInstallGuardFs(~symlinkPath="")
    let markerPath = "/registry/guarded/.blueprint-provenance"
    let fs: Ports.fileSystem = {
      ...base,
      lstat: path => path == markerPath
        ? Promise.resolve({isDirectory: () => false, isFile: () => true, isSymbolicLink: () => false}: Ports.lstatResult)
        : base.lstat(path),
    }
    Cli.copyTemplateToRegistry(
      ~deps=installGuardDeps(~fs), ~fs, ~path=pathAdapter, ~name="guarded", ~sourcePath="/source",
      ~registryRoot="/registry", ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: []},
      ~force=true, ~confirmOverwrite=_ => Promise.resolve(false),
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Refusing to install /source: source already contains a .blueprint-provenance marker")
      | Ok(_) => assert_false(true)
      }
      assert_eq(cpCalls.contents, 1)
      assert_eq(rmCalls.contents, 1)
      assert_eq(writeCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("copyTemplateToRegistry: preserves installed tree when marker inspection fails", resolve => {
    let (base, cpCalls, writeCalls, rmCalls) = makeInstallGuardFs(~symlinkPath="")
    let markerPath = "/registry/guarded/.blueprint-provenance"
    let fs: Ports.fileSystem = {
      ...base,
      lstat: path => path == markerPath ? Promise.reject(Obj.magic({"code": "EACCES"})) : base.lstat(path),
    }
    Cli.copyTemplateToRegistry(
      ~deps=installGuardDeps(~fs), ~fs, ~path=pathAdapter, ~name="guarded", ~sourcePath="/source",
      ~registryRoot="/registry", ~configPath="/config.yaml",
      ~globalConfig={templates: [], forceOverwrite: false, dryRun: false, timeout: 5, defaultAttributes: Dict.make(), registry: []},
      ~force=true, ~confirmOverwrite=_ => Promise.resolve(false),
    )->Promise.then(result => {
      switch result {
      | Error(message) => assert_eq(message, "Failed to install guarded: unable to verify marker absence after copy")
      | Ok(_) => assert_false(true)
      }
      assert_eq(cpCalls.contents, 1)
      assert_eq(rmCalls.contents, 0)
      assert_eq(writeCalls.contents, 0)
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("removeTemplateFromRegistry: removes directory and config entry", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let registryRoot = NodeJs.Path.join(tmpDir, "registry")
    let installed = NodeJs.Path.join(registryRoot, "api-route")
    let configPath = NodeJs.Path.join(tmpDir, "config.yaml")
    let cfg: Config.globalConfig = {
      templates: [],
      forceOverwrite: false,
      dryRun: false,
      timeout: 5,
      defaultAttributes: Dict.make(),
      registry: [{name: "api-route", source: "/workspace/_templates/api-route", path: installed}],
    }

    NodeJs.Fs.mkdir(installed, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.writeFile(NodeJs.Path.join(installed, "manifest.yaml"), "name: api-route\n"))
    ->Promise.then(_ => Config.saveGlobalAtPath(~fs=fsAdapter, ~path=pathAdapter, ~configPath, cfg))
    ->Promise.then(_ => Cli.removeTemplateFromRegistry(~deps={fs: fsAdapter, path: pathAdapter, process: NodeJsProcess.make(), shell: NodeJsShell.make(), argParser: NodeJsArgParser.make(), interactiveIO: NodeJsInteractiveIO.make(), yamlParser: NodeJsYamlParser.make(), ejs: NodeJsEjs.make(), fetcher: NodeJsFetcher.make(), pathSecurity: NodeJsPathSecurity.make(), shellBuilder: NodeJsShellBuilder.make(), envFilter: NodeJsEnvFilter.make(), hooks: TestPorts.stubHooks}, ~fs=fsAdapter, ~path=pathAdapter, ~name="api-route", ~configPath, ~globalConfig=cfg))
    ->Promise.then(result => {
      switch result {
      | Error(_) => {
          assert_false(true)
          resolve()
          Promise.resolve()
        }
      | Ok(updated) => {
          assert_eq(Array.length(updated.registry), 0)
          NodeJs.Fs.fileExists(installed)
          ->Promise.then(existsAfter => {
            assert_false(existsAfter)
            NodeJs.Fs.readFile(configPath, ~options={encoding: "utf8"})
          })
          ->Promise.then(saved => {
            switch Config.parseGlobal(saved) {
            | Ok(parsed) => assert_eq(Array.length(parsed.registry), 0)
            | Error(_) => assert_false(true)
            }
            resolve()
            Promise.resolve()
          })
        }
      }
    })
    ->ignore
  })

  testAsync("discovery order: local generator wins over registry duplicate", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let localRoot = NodeJs.Path.join(tmpDir, "project-templates")
    let registryRoot = NodeJs.Path.join(tmpDir, "global-templates")
    let classification = "api-route"
    let localGeneratorDir = NodeJs.Path.join(localRoot, classification)

    NodeJs.Fs.mkdir(localRoot, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(registryRoot, ~options={recursive: true}))
    ->Promise.then(_ => writeGeneratorFixture(~root=localRoot, ~name=classification))
    ->Promise.then(_ => writeGeneratorFixture(~root=registryRoot, ~name=classification))
    ->Promise.then(_ => {
      let paths = Cli.buildGenerateSearchPaths(
        ~deps={
          fs: fsAdapter,
          path: pathAdapter,
          process: NodeJsProcess.make(),
          shell: NodeJsShell.make(),
          argParser: NodeJsArgParser.make(),
          interactiveIO: NodeJsInteractiveIO.make(),
          yamlParser: NodeJsYamlParser.make(),
          ejs: NodeJsEjs.make(),
          fetcher: NodeJsFetcher.make(),
          pathSecurity: NodeJsPathSecurity.make(),
          shellBuilder: NodeJsShellBuilder.make(),
          envFilter: NodeJsEnvFilter.make(),
          hooks: TestPorts.stubHooks,
        },
        ~projectPaths=[localRoot],
        ~registry=[
          {
            name: classification,
            source: "/workspace/_templates/api-route",
            path: NodeJs.Path.join(registryRoot, classification),
          }: Config.templateSource,
        ],
        ~globalTemplates=[],
      )
      Discovery.discoverGenerators(
        ~fs=fsAdapter,
        ~path=pathAdapter,
        ~yamlParser=NodeJsYamlParser.make(),
        ~searchPaths=paths,
        (),
      )
    })
    ->Promise.then(generators => {
      switch Discovery.findByClassificationMeta(generators, classification) {
      | None => assert_false(true)
      | Some(found) => assert_eq(found.path, localGeneratorDir)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
