// ArchitectureGuard_test.res — regression guard for hexagonal boundaries.
//
// Enforces the architectural rule that domain and application layers must
// not contain direct references to infrastructure bindings (Bindings.*,
// NodeJs.*, Deno.*). Introduced as part of the
// restore-hexagonal-domain-and-app-layer change.
//
// Implementation: recursively walks the target directories using node:fs /
// node:path externals (ripgrep is not installed in this environment). Each
// .res file is read in full and scanned for the forbidden patterns. Empty
// result means the layer is clean. False positives in comments or strings
// would need manual review — the patterns here are specific enough that
// stray mentions are unlikely.

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
  String.includes(line, "Bindings.") ||
  String.includes(line, "NodeJs.") ||
  String.includes(line, "Deno.")
}

let scanForForbiddenRefs: string => array<string> = scanRoot => {
  let acc: ref<array<string>> = ref([])
  let skipped = ["node_modules"]

  let rec walk = dir => {
    if existsSync(dir) {
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
        } else if String.endsWith(entry.name, ".res") {
          let content = readFileSync(full, "utf8")
          let lines = Js.String.split("\n", content)
          let li = ref(0)
          while li.contents < Array.length(lines) {
            let line = Array.getUnsafe(lines, li.contents)
            li := li.contents + 1
            if checkLine(line) {
              acc := Array.concat(acc.contents, [full ++ ":" ++ Js.Int.toString(li.contents)])
            }
          }
        }
      }
    }
  }

  walk(scanRoot)
  acc.contents
}

open TestHelpers

suite("Architecture guard", () => {
  test("domain layer contains no Bindings/NodeJs/Deno references", () => {
    let violations = scanForForbiddenRefs("src/domain")
    assert_eq(Array.length(violations), 0)
  })

  test("application layer contains no Bindings/NodeJs/Deno references", () => {
    let violations = scanForForbiddenRefs("src/application")
    assert_eq(Array.length(violations), 0)
  })
})
