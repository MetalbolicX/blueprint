// ArchitectureGuard_test.res — regression guard for hexagonal boundaries.
//
// Enforces that domain and application layers do not reach into runtime
// bindings directly. Infrastructure adapters are intentionally exempt.
// The scan fails closed: an absent root or unreadable directory/file fails
// the test rather than silently certifying a partial tree.

type readdirOptions = {withFileTypes: bool}

type dirent = {name: string, isDirectory: unit => bool}

@module("node:fs")
external readdirSync: (string, readdirOptions) => array<dirent> = "readdirSync"

@module("node:fs")
external readFileSync: (string, string) => string = "readFileSync"

@module("node:fs")
external existsSync: string => bool = "existsSync"

@module("node:path")
external pathJoin: (string, string) => string = "join"

let checkLine: string => bool = line => {
  Js.String.match_(/Bindings\.[A-Z]/, line) != None ||
  Js.String.match_(/NodeJs\.[A-Z]/, line) != None ||
  Js.String.match_(/Deno\.[A-Z]/, line) != None ||
  Js.String.match_(/Ejs\.[A-Z]/, line) != None ||
  // Plan 055: application-layer module references move behind Ports.
  // Wrapper-module patterns are case-sensitive on the module name and
  // anchored at a non-identifier boundary (so `EngineHooks.` does not
  // match the `Hooks.` pattern). `Ports.fetcher`/`hooks` never match.
  Js.String.match_(/(?<![A-Za-z])Fetcher\./, line) != None ||
  Js.String.match_(/(?<![A-Za-z])PathSecurity\./, line) != None ||
  Js.String.match_(/(?<![A-Za-z])ShellBuilder\./, line) != None ||
  Js.String.match_(/(?<![A-Za-z])EnvFilter\./, line) != None ||
  Js.String.match_(/(?<![A-Za-z])Hooks\./, line) != None ||
  String.includes(line, "@module(\"node:")
}

let scanForForbiddenRefs = (~root: string) => {
  let scanRoot = root
  let acc: ref<array<string>> = ref([])
  let skipped = ["node_modules"]

  let rec walk = dir => {
    let entries = readdirSync(dir, {withFileTypes: true})
    let i = ref(0)
    while i.contents < Array.length(entries) {
      let entry = Array.getUnsafe(entries, i.contents)
      i := i.contents + 1
      let full = pathJoin(dir, entry.name)
      if entry.isDirectory() {
        let shouldSkip = Array.some(skipped, s => s == entry.name) || String.startsWith(entry.name, ".")
        if !shouldSkip {
          walk(full)
        }
      } else if String.endsWith(entry.name, ".res") || String.endsWith(entry.name, ".resi") {
        let content = readFileSync(full, "utf8")
        let lines = Js.String.split("\n", content)
        let li = ref(0)
        while li.contents < Array.length(lines) {
          let line = Array.getUnsafe(lines, li.contents)
          li := li.contents + 1
          if checkLine(line) {
            acc := Array.concat(acc.contents, [full ++ ":" ++ Int.toString(li.contents)])
          }
        }
      }
    }
  }

  if !existsSync(scanRoot) {
    failwith("Architecture guard expected directory to exist: " ++ scanRoot)
  }
  walk(scanRoot)
  acc.contents
}

open TestHelpers

suite("Architecture guard", () => {
  test("domain layer contains no forbidden binding references", () => {
    let violations = scanForForbiddenRefs(~root="src/domain")
    assert_eq(Array.length(violations), 0)
  })

  test("application layer contains no forbidden binding references", () => {
    let violations = scanForForbiddenRefs(~root="src/application")
    assert_eq(Array.length(violations), 0)
  })

  test("scanner fails closed when its root is missing", () => {
    let unique = Date.now()->Float.toInt->Int.toString ++ "-" ++ Math.random()->Float.toString
    let root = NodeJs.Path.join(NodeJs.Os.tmpdir(), "blueprint-architecture-guard-missing-" ++ unique)
    let failed = try {
      let _ = scanForForbiddenRefs(~root)
      false
    } catch {
    | _ => true
    }
    assert_true(failed)
  })

  testAsync("scanner flags raw Node imports and NodeJs references in .res and .resi fixtures", resolve => {
    let root = NodeJs.Os.makeStagingDir()
    let implementationPath = NodeJs.Path.join(root, "Fixture.res")
    let interfacePath = NodeJs.Path.join(root, "Fixture.resi")
    NodeJs.Fs.writeFile(implementationPath, "@module(\"node:fs\") external read: unit => string = \"readFileSync\"")
    ->Promise.then(_ => NodeJs.Fs.writeFile(interfacePath, "let runtime = NodeJs.Fs.fileExists"))
    ->Promise.then(_ => {
      let violations = scanForForbiddenRefs(~root)
      assert_eq(Array.length(violations), 2)
      assert_true(Array.some(violations, violation => String.includes(violation, "Fixture.res:1")))
      assert_true(Array.some(violations, violation => String.includes(violation, "Fixture.resi:1")))
      NodeJs.Fs.rm(root, ~options={recursive: true})->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->ignore
  })

  testAsync("scanner flags application-layer infrastructure module references (plan 055)", resolve => {
    let root = NodeJs.Os.makeStagingDir()
    let appPath = NodeJs.Path.join(root, "AppFixture.res")
    NodeJs.Fs.writeFile(appPath, "let go = () => Fetcher.fetch(\"https://example.com\")")
    ->Promise.then(_ => {
      let violations = scanForForbiddenRefs(~root)
      assert_eq(Array.length(violations), 1)
      assert_true(Array.some(violations, violation => String.includes(violation, "AppFixture.res:1")))
      NodeJs.Fs.rm(root, ~options={recursive: true})->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
    })
    ->ignore
  })
})
