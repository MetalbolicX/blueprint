// IntegrationE2E_test — full pipeline end-to-end test with real template rendering
// Exercises Engine.run with a generator that has a template with EJS conditionals,
// verifying that output file content matches expected method handlers.

open TestHelpers

let deps: Ports.deps = {
  fs: NodeJsFileSystem.make(),
  path: NodeJsPath.make(),
  process: NodeJsProcess.make(),
  shell: NodeJsShell.make(),
  interactiveIO: NodeJsInteractiveIO.make(()),
  argParser: NodeJsArgParser.make(),
  yamlParser: NodeJsYamlParser.make(),
  ejs: NodeJsEjs.make(),
  fetcher: NodeJsFetcher.make(),
  pathSecurity: NodeJsPathSecurity.make(),
  shellBuilder: NodeJsShellBuilder.make(),
  envFilter: NodeJsEnvFilter.make(),
  hooks: NodeJsHooks.make(),
}

suite("Integration E2E", () => {
  testAsync("full pipeline: generates file with correct conditional methods", resolve => {
    let tmpDir = NodeJs.Os.makeStagingDir()
    let genPath = NodeJs.Path.join(tmpDir, "e2e-test")
    let actionPath = NodeJs.Path.join(genPath, "new")
    let outputDir = NodeJs.Path.join(tmpDir, "output")
    let outputFile = "product.router.js"
    let outputPath = NodeJs.Path.join(outputDir, outputFile)

    let cleanup = () => {
      NodeJs.Fs.rm(tmpDir, ~options={recursive: true})
      ->Promise.then(_ => {
        resolve()
        Promise.resolve()
      })
      ->ignore
    }

    NodeJs.Fs.mkdir(actionPath, ~options={recursive: true})
    ->Promise.then(_ => NodeJs.Fs.mkdir(outputDir, ~options={recursive: true}))
    ->Promise.then(_ => {
      // Create template with EJS conditional blocks for HTTP method handlers
      let tmplBody =
        [
          "",
          "import { Router } from 'express';",
          "const router = Router();",
          "const ProductModel = {",
          "  findAll: async () => [],",
          "  findById: async (id) => null,",
          "  create: async (data) => data,",
          "  update: async (id, data) => data,",
          "  remove: async (id) => true,",
          "};",
          "",
          "<% if (methods.includes('GET')) { %>",
          "router.get('/products', async (req, res) => { res.json({}); });",
          "router.get('/products/:id', async (req, res) => { res.json({}); });",
          "<% } %>",
          "",
          "<% if (methods.includes('POST')) { %>",
          "router.post('/products', async (req, res) => { res.status(201).json({}); });",
          "<% } %>",
          "",
          "<% if (methods.includes('PUT')) { %>",
          "router.put('/products/:id', async (req, res) => { res.json({}); });",
          "<% } %>",
          "",
          "<% if (methods.includes('DELETE')) { %>",
          "router.delete('/products/:id', async (req, res) => { res.status(204).send(); });",
          "<% } %>",
          "",
          "export default router;",
        ]->Array.join("\n")

      let tmpl: Template.template = {
        sourcePath: NodeJs.Path.join(actionPath, "product.router.js.ejs.t"),
        directives: [Template.To(outputFile)],
        body: tmplBody,
      }

      let gen: Discovery.generator = {
        name: "e2e-test",
        path: genPath,
        templates: [tmpl],
      }

      // Provide GET and POST via CLI attributes; PUT and DELETE omitted
      let cliAttrs = Dict.make()
      Dict.set(cliAttrs, "methods", Context.Values(["GET", "POST"]))

      Engine.run(
        ~generator=gen,
        ~name="product",
        ~cliAttributes=cliAttrs,
        ~outputDir,
        ~force=true,
        ~deps,
      )
    })
    ->Promise.then(result => {
      switch result {
      | Ok(_r) =>
        NodeJs.Fs.readFile(outputPath, ~options={encoding: "utf8"})
        ->Promise.then(content => {
          // Verify GET and POST handlers exist
          assert_true(String.includes(content, "router.get"))
          assert_true(String.includes(content, "router.post"))

          // Verify PUT and DELETE handlers are absent
          assert_false(String.includes(content, "router.put"))
          assert_false(String.includes(content, "router.delete"))

          // Verify route path appears
          assert_true(String.includes(content, "/products"))

          cleanup()
          Promise.resolve()
        })
        ->Promise.catch(_ => {
          assert_false(true)
          cleanup()
          Promise.resolve()
        })
      | Error(_e) =>
        assert_false(true)
        cleanup()
        Promise.resolve()
      }
    })
    ->Promise.catch(_ => {
      assert_false(true)
      cleanup()
      Promise.resolve()
    })
    ->ignore
  })
})
