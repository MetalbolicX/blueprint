open TestHelpers

suite("Generator Scaffold", () => {
  testAsync("meta-generator templates exist", resolve => {
    let manifestPath = NodeJs.Path.join(
      NodeJs.Path.join("_templates", "generator"),
      "manifest.yaml",
    )
    let targetManifestTemplatePath = NodeJs.Path.join(
      NodeJs.Path.join(NodeJs.Path.join("_templates", "generator"), "new"),
      "manifest.ejs.t",
    )
    let targetStubTemplatePath = NodeJs.Path.join(
      NodeJs.Path.join(NodeJs.Path.join("_templates", "generator"), "new"),
      "example.ejs.t.ejs.t",
    )

    NodeJs.Fs.fileExists(manifestPath)
    ->Promise.then(manifestExists => {
      assert_true(manifestExists)
      NodeJs.Fs.fileExists(targetManifestTemplatePath)
    })
    ->Promise.then(targetManifestExists => {
      assert_true(targetManifestExists)
      NodeJs.Fs.fileExists(targetStubTemplatePath)
    })
    ->Promise.then(targetStubExists => {
      assert_true(targetStubExists)
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
