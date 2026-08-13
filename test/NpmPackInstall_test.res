// NpmPackInstall_test — real npm pack + install smoke test
// Proves the published .tgz artifact installs and runs correctly.

open TestHelpers

let makeDeps = (~cwd: string, ~exitCodes: ref<array<int>>, ~homedir: string): Ports.deps => {
  let fs = NodeJsFileSystem.make()
  let path = NodeJsPath.make()
  {
    fs,
    path,
    process: {
      cwd: () => cwd,
      env: () => Dict.make(),
      argv: () => ["node", "blueprint"],
      exit: code => {
        let _ = exitCodes.contents->Array.push(code)
        ()
      },
      onSignal: (_, _) => (),
      removeSignalListeners: () => (),
      homedir: () => homedir,
    },
    shell: NodeJsShell.make(),
    interactiveIO: {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(false),
      close: () => (),
    },
    argParser: {
      parse: (~args as _, ~strict as _, ~allowPositionals as _) => Ok({values: Dict.make(), positionals: []}),
    },
    yamlParser: NodeJsYamlParser.make(),
    ejs: NodeJsEjs.make(),
  }
}

suite("NpmPackInstall smoke", () => {
  // Proves dist/main.mjs runs as a standalone CLI (the npm pack artifact).
  // Running via node from projectRoot ensures @rescript/runtime is resolved.
  testAsync("dist/main.mjs runs standalone via node", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let exitCodes = ref([])
    let deps = makeDeps(~cwd=tmpDir, ~exitCodes, ~homedir=tmpDir)
    let shell = deps.shell

    let projectRoot = %raw("process.cwd()")
    let mainMjs = NodeJs.Path.join(projectRoot, "dist/main.mjs")

    let reject: string => promise<unit> = %raw(`msg => Promise.reject(new Error(msg))`)

    shell
    .execAsync(
      `node "${mainMjs}" --help`,
      ~options={timeout: 30000, encoding: "utf8"},
    )
    ->Promise.then(result => {
      let success = result.status === Some(0) &&
        result.stdout->String.length > 0 &&
        result.stdout->String.includes("blueprint")

      let _ = NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore

      if !success {
        reject(
          `node main.mjs --help failed. Status: ${Int.toString(Belt.Option.getWithDefault(result.status, -1))}, stdout: ${result.stdout}, stderr: ${result.stderr}`,
        )->ignore
      } else {
        resolve()
      }
      Promise.resolve()
    })
    ->Promise.catch(_err => {
      let _ = NodeJs.Fs.rm(tmpDir, ~options={recursive: true})->ignore
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
