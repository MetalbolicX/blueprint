// Manifest_test — manifest parsing and validation tests

open TestHelpers
open TestPorts

suite("Manifest", () => {
  test("parse: minimal valid manifest", () => {
    let yaml = "name: test\nclassification: test\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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

  test("parse: multi-select prompt with options", () => {
    let yaml = "name: test\nclassification: test\nprompts:\n  - name: colors\n    type: multi-select\n    options:\n      - red\n      - green\n      - blue\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) => switch m.prompts {
      | Some(prompts) => switch prompts[0] {
        | Some(p) => {
            assert_eq(p.promptType, Manifest.MultiSelect)
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

  test("validate: multi-select without options", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "test",
      prompts: [
        {
          name: "colors",
          promptType: Manifest.MultiSelect,
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
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

  test("appendPromptPreservingComments: appends prompt and keeps comments", () => {
    let yaml =
      "# generator manifest\nname: test\nclassification: test\n# prompts section\nprompts:\n  # existing prompt\n  - name: existing\n    type: input\n    description: Existing prompt\n"

    let newPrompt: Manifest.prompt = {
      name: "componentName",
      promptType: Manifest.Input,
      description: "Component name",
      default: "Button",
    }

    let result = ManifestYamlEditor.appendPromptPreservingComments(~yamlContent=yaml, ~prompt=newPrompt)
    switch result {
    | Ok(updatedYaml) => {
        assert_true(String.includes(updatedYaml, "# generator manifest"))
        assert_true(String.includes(updatedYaml, "# prompts section"))
        assert_true(String.includes(updatedYaml, "# existing prompt"))

        switch Manifest.parse(~yamlParser=stubYamlParser, ~yaml=updatedYaml) {
        | Ok(manifest) =>
          switch manifest.prompts {
          | Some(prompts) => {
              assert_eq(Array.length(prompts), 2)
              switch prompts[1] {
              | Some(appended) => {
                  assert_eq(appended.name, "componentName")
                  assert_eq(appended.description, "Component name")
                  switch appended.default {
                  | Some(v) => assert_eq(v, "Button")
                  | None => assert_false(true)
                  }
                }
              | None => assert_false(true)
              }
            }
          | None => assert_false(true)
          }
        | Error(_) => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("appendPromptPreservingComments: creates prompts list when missing", () => {
    let yaml = "# no prompts yet\nname: test\nclassification: test\n"

    let newPrompt: Manifest.prompt = {
      name: "feature",
      promptType: Manifest.Select,
      description: "Pick feature",
      options: [
        {label: "A", value: "a"},
        {label: "B", value: "b"},
      ],
    }

    let result = ManifestYamlEditor.appendPromptPreservingComments(~yamlContent=yaml, ~prompt=newPrompt)
    switch result {
    | Ok(updatedYaml) => {
        assert_true(String.includes(updatedYaml, "# no prompts yet"))
        switch Manifest.parse(~yamlParser=stubYamlParser, ~yaml=updatedYaml) {
        | Ok(manifest) =>
          switch manifest.prompts {
          | Some(prompts) => {
              assert_eq(Array.length(prompts), 1)
              switch prompts[0] {
              | Some(appended) => {
                  assert_eq(appended.name, "feature")
                  assert_eq(appended.promptType, Manifest.Select)
                  switch appended.options {
                  | Some(options) => assert_eq(Array.length(options), 2)
                  | None => assert_false(true)
                  }
                }
              | None => assert_false(true)
              }
            }
          | None => assert_false(true)
          }
        | Error(_) => assert_false(true)
        }
      }
    | Error(_) => assert_false(true)
    }
  })

  test("appendPromptPreservingComments: returns error for invalid yaml", () => {
    let invalidYaml = "name: [unterminated"
    let newPrompt: Manifest.prompt = {
      name: "x",
      promptType: Manifest.Input,
      description: "x",
    }

    let result = ManifestYamlEditor.appendPromptPreservingComments(~yamlContent=invalidYaml, ~prompt=newPrompt)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_true(String.length(msg) > 0)
    }
  })

  // --- validate: error collection (fail-fast contract) ---

  test("validate: collects multiple errors together (missing classification + select-no-options)", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "",
      prompts: [
        {
          name: "type",
          promptType: Manifest.Select,
          description: "Pick a type",
        },
      ],
    }
    switch Manifest.validate(manifest) {
    | Error(errors) => {
        // Both errors should be reported together, not collapsed into one
        assert_true(Array.length(errors) >= 2)
        let fields = errors->Array.map(e => e.field)
        let hasClassification = fields->Array.some(f => f == "classification")
        let hasOptions = fields->Array.some(f => f == "prompts.options")
        assert_true(hasClassification)
        assert_true(hasOptions)
      }
    | Ok(_) => assert_false(true)
    }
  })

  test("validate: error message says select prompt requires options", () => {
    let manifest: Manifest.manifest = {
      name: "test",
      classification: "test",
      prompts: [
        {
          name: "type",
          promptType: Manifest.Select,
          description: "Pick a type",
        },
      ],
    }
    switch Manifest.validate(manifest) {
    | Error(errors) => {
        let messages = errors->Array.map(e => e.message)
        let hasSelectMsg = messages->Array.some(m =>
          String.includes(m, "select prompt requires options")
        )
        assert_true(hasSelectMsg)
      }
    | Ok(_) => assert_false(true)
    }
  })

  test("validationErrorsToString: formats multiple errors joined by semicolon", () => {
    let errors: array<Manifest.validationError> = [
      {field: "classification", message: "classification is required"},
      {field: "prompts.options", message: "select prompt requires options"},
    ]
    let formatted = Manifest.validationErrorsToString(errors)
    assert_true(String.includes(formatted, "classification: classification is required"))
    assert_true(String.includes(formatted, "prompts.options: select prompt requires options"))
    assert_true(String.includes(formatted, "; "))
  })

  // --- Step 3: reject unknown top-level manifest keys ---

  test("parse: rejects unknown top-level keys", () => {
    let yaml = "name: x\nclassification: y\nbogusField: 123\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => assert_true(String.includes(msg, "bogusField"))
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: rejects multiple unknown top-level keys", () => {
    let yaml = "name: x\nclassification: y\nunknown1: val1\nunknown2: val2\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => {
        assert_true(String.includes(msg, "unknown1"))
        assert_true(String.includes(msg, "unknown2"))
      }
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: accepts manifest with only known keys", () => {
    let yaml = "name: x\nclassification: y\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) => {
        assert_eq(m.name, "x")
        assert_eq(m.classification, "y")
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: accepts manifest with optional metadata key", () => {
    let yaml = "name: x\nclassification: y\nmetadata:\n  author: someone\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) => assert_true(m.metadata != None)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: accepts manifest with optional prompts key", () => {
    let yaml = "name: x\nclassification: y\nprompts:\n  - name: path\n    type: input\n    description: Output path\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) => assert_true(m.prompts != None)
    | Error(_) => assert_false(true)
    }
  })

  // --- generator-level hook declarations (plan 031) ---

  test("parse: pre_generate relative path parses and is preserved", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  pre_generate: scripts/read-package-name.mjs\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) =>
      switch m.hooks {
      | Some(gh) =>
        switch gh.preGenerate {
        | Some(p) => assert_eq(p, "scripts/read-package-name.mjs")
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

  test("parse: post_generate relative path parses and is preserved", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  post_generate: scripts/setup-rescript.mjs\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) =>
      switch m.hooks {
      | Some(gh) =>
        switch gh.postGenerate {
        | Some(p) => assert_eq(p, "scripts/setup-rescript.mjs")
        | None => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: both hooks declared parses both paths", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  pre_generate: scripts/pre.mjs\n  post_generate: scripts/post.mjs\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) =>
      switch m.hooks {
      | Some(gh) =>
        switch (gh.preGenerate, gh.postGenerate) {
        | (Some(p), Some(q)) => {
            assert_eq(p, "scripts/pre.mjs")
            assert_eq(q, "scripts/post.mjs")
          }
        | _ => assert_false(true)
        }
      | None => assert_false(true)
      }
    | Error(_) => assert_false(true)
    }
  })

  test("parse: no hooks is backward-compatible", () => {
    let yaml = "name: x\nclassification: y\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Ok(m) => assert_true(m.hooks == None)
    | Error(_) => assert_false(true)
    }
  })

  test("parse: absolute path in pre_generate is rejected", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  pre_generate: /tmp/evil.sh\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => assert_true(String.includes(msg, "absolute paths are not allowed"))
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: parent-segment path in pre_generate is rejected", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  pre_generate: ../evil.sh\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => assert_true(String.includes(msg, "'..' segments are not allowed"))
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: absolute path in post_generate is rejected", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  post_generate: /abs/evil.sh\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => assert_true(String.includes(msg, "absolute paths are not allowed"))
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: hooks value must be an object", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  - not an object\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => assert_true(String.includes(msg, "hooks must be an object"))
    | Ok(_) => assert_false(true)
    }
  })

  test("parse: pre_generate must be a string", () => {
    let yaml = "name: x\nclassification: y\nhooks:\n  pre_generate:\n    command: echo\n"
    let result = Manifest.parse(~yamlParser=stubYamlParser, ~yaml=yaml)
    switch result {
    | Error(msg) => assert_true(String.includes(msg, "pre_generate must be a string"))
    | Ok(_) => assert_false(true)
    }
  })
})
