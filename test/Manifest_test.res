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

  test("parse: prompt with when field", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: color\n    type: input\n    description: Color\n    when: answers.theme == \"custom\"\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => {
            assert_eq(p.name, "color")
            switch p.when_ {
            | Some(w) => assert_eq(w, "answers.theme == \"custom\"")
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

  test("parse: prompt with validate pattern and message", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: email\n    type: input\n    description: Email\n    validate:\n      pattern: \"^[a-z]+@[a-z]+\\\\.[a-z]+$\"\n      message: Must be a valid email\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => {
            assert_eq(p.name, "email")
            switch p.validate {
            | Some(v) => {
                assert_true(String.length(v.pattern) > 0)
                assert_eq(v.message, "Must be a valid email")
              }
            | None => assert_false(true)
            }
          }
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(e) => {
        Console.log(e)
        assert_false(true)
      }
    }
  })

  test("parse: select prompt with options as objects", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: type\n    type: select\n    options:\n      - label: React Component\n        value: component\n      - label: Custom Hook\n        value: hook\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => {
            assert_eq(p.promptType, Manifest.Select)
            switch p.options {
            | Some(opts) => {
                assert_eq(Array.length(opts), 2)
                switch opts[0] {
                | Some(o) => {
                    assert_eq(o.label, "React Component")
                    assert_eq(o.value, "component")
                  }
                | None => assert_false(true)
                }
              }
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

  test("parse: backward compat — options as plain string array", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: type\n    type: select\n    options:\n      - component\n      - hook\n      - utility\n"
    let result = Manifest.parse(yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => {
            switch p.options {
            | Some(opts) => {
                assert_eq(Array.length(opts), 3)
                // Plain strings should map to label=value
                switch opts[0] {
                | Some(o) => {
                    assert_eq(o.label, "component")
                    assert_eq(o.value, "component")
                  }
                | None => assert_false(true)
                }
              }
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
})
