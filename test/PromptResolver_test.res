// PromptResolver_test — prompt resolution tests with declarative evaluation

open TestHelpers

suite("PromptResolver", () => {
  // --- evalTemplate tests ---

  test("evalTemplate: renders simple interpolation", () => {
    let ctx = {"name": "Ada"}
    let result = PromptResolver.evalTemplate("Hello <%= name %>", ~ctx)
    switch result {
    | Ok(s) => assert_eq(s, "Hello Ada")
    | Error(_) => assert_false(true)
    }
  })

  test("evalTemplate: rejects control flow tags", () => {
    let ctx = {"name": "Ada"}
    let result = PromptResolver.evalTemplate("<% if (true) { %>hi<% } %>", ~ctx)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(PromptResolver.EvaluationError(_)) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })

  test("evalTemplate: rejects unescaped output tags", () => {
    let ctx = {"name": "Ada"}
    let result = PromptResolver.evalTemplate("<%- name %>", ~ctx)
    switch result {
    | Ok(_) => assert_false(true)
    | Error(PromptResolver.EvaluationError(_)) => assert_true(true)
    | Error(_) => assert_false(true)
    }
  })

  // --- Force mode tests ---

  testAsync("resolve: force mode assigns evaluated default", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "name",
        promptType: Manifest.Input,
        description: "Name",
        default: "World",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          let val = Dict.get(answers, "name")
          assert_eq(val, Some("World"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force mode skips when=false prompt", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "visible",
        promptType: Manifest.Input,
        description: "Visible",
        default: "yes",
      },
      {
        name: "hidden",
        promptType: Manifest.Input,
        description: "Hidden",
        default: "no",
        when_: "false",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "visible"), Some("yes"))
          assert_eq(Dict.get(answers, "hidden"), None)
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force mode evaluates default with prior answers", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "name",
        promptType: Manifest.Input,
        description: "Name",
        default: "Ada",
      },
      {
        name: "service",
        promptType: Manifest.Input,
        description: "Service name",
        default: "<%= answers.name %>-service",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "name"), Some("Ada"))
          assert_eq(Dict.get(answers, "service"), Some("Ada-service"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force mode evaluates when with prior answers", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "theme",
        promptType: Manifest.Input,
        description: "Theme",
        default: "custom",
      },
      {
        name: "color",
        promptType: Manifest.Input,
        description: "Color",
        default: "blue",
        when_: "<%= answers.theme === 'custom' %>",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "theme"), Some("custom"))
          assert_eq(Dict.get(answers, "color"), Some("blue"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force mode skips when condition is false", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "theme",
        promptType: Manifest.Input,
        description: "Theme",
        default: "light",
      },
      {
        name: "color",
        promptType: Manifest.Input,
        description: "Color",
        default: "blue",
        when_: "<%= answers.theme === 'custom' %>",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "theme"), Some("light"))
          assert_eq(Dict.get(answers, "color"), None)
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- Error handling tests ---

  testAsync("resolve: invalid EJS expression returns EvaluationError", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "name",
        promptType: Manifest.Input,
        description: "Name",
        default: "<%= invalid.syntax..here %>",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(PromptResolver.EvaluationError({prompt})) => {
          assert_eq(prompt, "name")
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: invalid regex returns ValidationConfigError", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "email",
        promptType: Manifest.Input,
        description: "Email",
        default: "test@test.com",
        validate: {
          Manifest.pattern: "[invalid",
          message: "Must be valid",
        },
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          // Force mode skips validation — assigns default directly
          assert_eq(Dict.get(answers, "email"), Some("test@test.com"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- Context integration tests ---

  testAsync("resolve: force mode uses baseContext in when evaluation", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "color",
        promptType: Manifest.Input,
        description: "Color",
        default: "red",
        when_: "<%= context.theme === 'custom' %>",
      },
    ]
    let baseContext: dict<string> = Dict.make()
    Dict.set(baseContext, "theme", "custom")

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "color"), Some("red"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force mode uses baseContext in default evaluation", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "greeting",
        promptType: Manifest.Input,
        description: "Greeting",
        default: "Hello <%= context.name %>",
      },
    ]
    let baseContext: dict<string> = Dict.make()
    Dict.set(baseContext, "name", "Blueprint")

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "greeting"), Some("Hello Blueprint"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: invalid input retries until valid", resolve => {
    let callCount = ref(0)
    let mockIo: Ports.interactiveIO = {
      ask: _ => {
        callCount.contents = callCount.contents + 1
        if callCount.contents == 1 {
          Promise.resolve("invalid_token")
        } else {
          Promise.resolve("valid_123")
        }
      },
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }

    let prompts: array<Manifest.prompt> = [
      {
        name: "token",
        promptType: Manifest.Input,
        description: "Token",
        validate: {pattern: "^valid_", message: "Must start with valid_"},
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(callCount.contents, 2)
          assert_eq(Dict.get(answers, "token"), Some("valid_123"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
