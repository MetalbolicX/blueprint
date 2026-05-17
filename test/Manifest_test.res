// Manifest_test — manifest parsing and validation tests

open TestHelpers

suite("Manifest", () => {
  test("parse: minimal valid manifest", () => {
    let yaml = "name: test\nclassification: test\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => {
        assert_eq(m.name, "test")
        assert_eq(m.classification, "test")
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: manifest with prompts", () => {
    let yaml = "name: component\nclassification: component\nprompts:\n  - name: path\n    type: input\n    description: Output path\n    default: src/components\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => {
        assert_eq(m.name, "component")
        switch m.prompts {
        | Some(prompts) => {
            assert_eq(Array.length(prompts), 1)
            switch prompts[0] {
            | Some(p) => assert_eq(p.name, "path")
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      }
    | Error(e) => {
        Console.log(e)
        assert_false(true)
      }
    }
  })

  test("parse: select prompt with options", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: type\n    type: select\n    options:\n      - component\n      - hook\n      - utility\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => {
            assert_eq(p.promptType, Manifest.Select)
            switch p.options {
            | Some(opts) => assert_eq(Array.length(opts), 3)
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: confirm prompt", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: typescript\n    type: confirm\n    description: Use TypeScript\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => assert_eq(p.promptType, Manifest.Confirm)
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: metadata", () => {
    let yaml = "name: test\nclassification: test\nmetadata:\n  author: someone\n  version: 1.0\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.metadata {
      | Some(meta) => {
          let author = Dict.get(meta, "author")
          assert_true(author != None)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("validate: missing classification", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "",
    }
    let result = Manifest.validate(manifest)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("validate: empty prompt name", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "test",
      prompts: [
        {
          name: "",
          promptType: Manifest.Input,
          description: "test",
        },
      ],
    }
    let result = Manifest.validate(manifest)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("validate: select without options", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "test",
      prompts: [
        {
          name: "type",
          promptType: Manifest.Select,
          description: "test",
        },
      ],
    }
    let result = Manifest.validate(manifest)
    switch result {
    | Error(_) => assert_true(true)
    | Ok(_) => assert_false(true)
    }
  })

  test("validate: valid manifest", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "test",
      prompts: [
        {
          name: "name",
          promptType: Manifest.Input,
          description: "Component name",
          default: "MyComponent",
        },
      ],
    }
    let result = Manifest.validate(manifest)
    switch result {
    | Ok(_) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })
})
