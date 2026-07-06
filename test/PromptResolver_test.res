// PromptResolver_test — prompt resolution tests with declarative evaluation

open TestHelpers

// --- Console spy for testing interactive error/warning output ---

let installConsoleLogSpy: unit => unit = %raw(`
  function() {
    globalThis.__testMessages = [];
    globalThis.__originalConsoleLog = console.log;
    console.log = function(msg) { globalThis.__testMessages.push(msg); };
  }
`)

let restoreConsoleLog: unit => unit = %raw(`
  function() {
    if (globalThis.__originalConsoleLog) {
      console.log = globalThis.__originalConsoleLog;
      delete globalThis.__originalConsoleLog;
    }
  }
`)

let resetTestMessages: unit => unit = %raw(`
  function() { globalThis.__testMessages = []; }
`)

let getTestMessages: unit => array<string> = %raw(`
  function() { return globalThis.__testMessages || []; }
`)

// Convenience: build a mock interactiveIO that returns the next scripted answer
// on each `ask` call. Confirm answers default to true.
let makeScriptedIo = (answers: array<string>): Ports.interactiveIO => {
  let idx = ref(0)
  {
    ask: _ => {
      let i = idx.contents
      idx.contents = i + 1
      switch answers[i] {
      | Some(a) => Promise.resolve(a)
      | None => Promise.resolve("")
      }
    },
    askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
    close: () => (),
  }
}

let makeCountingIo = (answers: array<string>): (Ports.interactiveIO, ref<int>) => {
  let callCount = ref(0)
  let io = makeScriptedIo(answers)
  let wrappedIo: Ports.interactiveIO = {
    ask: q => {
      callCount.contents = callCount.contents + 1
      io.ask(q)
    },
    askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
    close: () => (),
  }
  (wrappedIo, callCount)
}

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

  // --- MultiSelect tests ---

  testAsync("resolve: multi-select interactive returns comma-separated values", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve("1,3"),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "colors",
        promptType: Manifest.MultiSelect,
        description: "Select colors",
        options: [
          {label: "Red", value: "red"},
          {label: "Green", value: "green"},
          {label: "Blue", value: "blue"},
          {label: "Yellow", value: "yellow"},
        ],
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "colors"), Some("red,blue"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: multi-select force mode evaluates default", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "colors",
        promptType: Manifest.MultiSelect,
        description: "Select colors",
        default: "red,blue",
        options: [
          {label: "Red", value: "red"},
          {label: "Green", value: "green"},
          {label: "Blue", value: "blue"},
        ],
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => {
          assert_eq(Dict.get(answers, "colors"), Some("red,blue"))
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

  // --- Fail-fast: select without options ---

  testAsync("resolve: interactive Select with options=None returns MissingOptionsError", resolve => {
    let askCalled = ref(false)
    let mockIo: Ports.interactiveIO = {
      ask: _ => {
        askCalled.contents = true
        Promise.resolve("anything")
      },
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "type",
        promptType: Manifest.Select,
        description: "Pick a type",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(PromptResolver.MissingOptionsError({prompt, message})) => {
          assert_eq(prompt, "type")
          assert_true(String.includes(message, "select prompt requires options"))
        }
      | Error(_) => assert_false(true)
      }
      assert_false(askCalled.contents)
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: interactive MultiSelect with options=None returns MissingOptionsError", resolve => {
    let askCalled = ref(false)
    let mockIo: Ports.interactiveIO = {
      ask: _ => {
        askCalled.contents = true
        Promise.resolve("1")
      },
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "colors",
        promptType: Manifest.MultiSelect,
        description: "Pick colors",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(PromptResolver.MissingOptionsError({prompt, message})) => {
          assert_eq(prompt, "colors")
          assert_true(String.includes(message, "select prompt requires options"))
        }
      | Error(_) => assert_false(true)
      }
      assert_false(askCalled.contents)
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force-mode Select with options=None returns MissingOptionsError", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "type",
        promptType: Manifest.Select,
        description: "Pick a type",
        default: "anything",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(PromptResolver.MissingOptionsError({prompt, message})) => {
          assert_eq(prompt, "type")
          assert_true(String.includes(message, "select prompt requires options"))
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: force-mode MultiSelect with options=None returns MissingOptionsError", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve(""),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "colors",
        promptType: Manifest.MultiSelect,
        description: "Pick colors",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=true, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(_) => assert_false(true)
      | Error(PromptResolver.MissingOptionsError({prompt, message: _message})) => {
          assert_eq(prompt, "colors")
        }
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  testAsync("resolve: Input prompt without options is allowed (no MissingOptionsError)", resolve => {
    let mockIo: Ports.interactiveIO = {
      ask: _ => Promise.resolve("answer"),
      askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
      close: () => ()
    }
    let prompts: array<Manifest.prompt> = [
      {
        name: "name",
        promptType: Manifest.Input,
        description: "Your name",
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      switch result {
      | Ok(answers) => assert_eq(Dict.get(answers, "name"), Some("answer"))
      | Error(_) => assert_false(true)
      }
      mockIo.close()
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- _validateSelectInput pure helper tests (3.1) ---

  let colorOptions: array<Manifest.promptOption> = [
    {label: "Red", value: "red"},
    {label: "Green", value: "green"},
    {label: "Blue", value: "blue"},
  ]

  test("_validateSelectInput: valid number resolves to option value", () => {
    let result = PromptResolver._validateSelectInput(~answer="2", ~opts=colorOptions, ~default="red")
    switch result {
    | Ok(v) => assert_eq(v, "green")
    | Error(_) => assert_false(true)
    }
  })

  test("_validateSelectInput: non-numeric returns Please-enter-a-number error", () => {
    let result = PromptResolver._validateSelectInput(~answer="abc", ~opts=colorOptions, ~default="red")
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_eq(msg, "Please enter a number")
    }
  })

  test("_validateSelectInput: out-of-range returns between-1-and-N error", () => {
    let result = PromptResolver._validateSelectInput(~answer="9", ~opts=colorOptions, ~default="red")
    switch result {
    | Ok(_) => assert_false(true)
    | Error(msg) => assert_eq(msg, "Please enter a number between 1 and 3")
    }
  })

  test("_validateSelectInput: empty input resolves to default without error", () => {
    let result = PromptResolver._validateSelectInput(~answer="", ~opts=colorOptions, ~default="red")
    switch result {
    | Ok(v) => assert_eq(v, "red")
    | Error(_) => assert_false(true)
    }
  })

  test("_validateSelectInput: whitespace-only input resolves to default", () => {
    let result = PromptResolver._validateSelectInput(~answer="   ", ~opts=colorOptions, ~default="blue")
    switch result {
    | Ok(v) => assert_eq(v, "blue")
    | Error(_) => assert_false(true)
    }
  })

  // --- _tokenizeMultiSelect pure helper tests (3.2) ---

  test("_tokenizeMultiSelect: all-valid tokens return all values, no invalid", () => {
    let (valid, invalid) = PromptResolver._tokenizeMultiSelect(~answer="1,3", ~opts=colorOptions)
    assert_eq(valid, ["red", "blue"])
    assert_eq(invalid, [])
  })

  test("_tokenizeMultiSelect: mixed valid/invalid splits correctly", () => {
    let (valid, invalid) = PromptResolver._tokenizeMultiSelect(~answer="2, x", ~opts=colorOptions)
    assert_eq(valid, ["green"])
    assert_eq(invalid, ["x"])
  })

  test("_tokenizeMultiSelect: zero-valid tokens returns empty valid and all invalid", () => {
    let (valid, invalid) = PromptResolver._tokenizeMultiSelect(~answer="x, y", ~opts=colorOptions)
    assert_eq(valid, [])
    assert_eq(invalid, ["x", "y"])
  })

  test("_tokenizeMultiSelect: out-of-range numeric is treated as invalid", () => {
    let (valid, invalid) = PromptResolver._tokenizeMultiSelect(~answer="9", ~opts=colorOptions)
    assert_eq(valid, [])
    assert_eq(invalid, ["9"])
  })

  test("_tokenizeMultiSelect: ignores empty tokens between commas", () => {
    let (valid, invalid) = PromptResolver._tokenizeMultiSelect(~answer="1,,3", ~opts=colorOptions)
    assert_eq(valid, ["red", "blue"])
    assert_eq(invalid, [])
  })

  // --- Select retry behavior with mocked interactiveIO (3.3) ---

  testAsync("resolve: Select re-prompts on non-numeric and out-of-range", resolve => {
    installConsoleLogSpy()
    resetTestMessages()
    let (mockIo, callCount) = makeCountingIo(["abc", "9", "2"])
    let prompts: array<Manifest.prompt> = [
      {
        name: "color",
        promptType: Manifest.Select,
        description: "Pick a color",
        options: colorOptions,
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      // Capture and restore BEFORE assertions so PASS/FAIL output prints
      let msgs = getTestMessages()
      let capturedAnswers = switch result {
      | Ok(answers) => Some(Dict.get(answers, "color"))
      | Error(_) => None
      }
      let capturedCalls = callCount.contents
      mockIo.close()
      restoreConsoleLog()

      switch capturedAnswers {
      | Some(color) => {
          assert_eq(capturedCalls, 3)
          assert_eq(color, Some("green"))
          assert_eq(Array.length(msgs), 2)
          switch msgs[0] {
          | Some(m) => assert_eq(m, "Error: Please enter a number")
          | None => assert_false(true)
          }
          switch msgs[1] {
          | Some(m) => assert_eq(m, "Error: Please enter a number between 1 and 3")
          | None => assert_false(true)
          }
        }
      | None => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- Empty Select resolves to default without re-prompt (3.5) ---

  testAsync("resolve: empty Select answer resolves to default on first ask", resolve => {
    installConsoleLogSpy()
    resetTestMessages()
    let (mockIo, callCount) = makeCountingIo([""])
    let prompts: array<Manifest.prompt> = [
      {
        name: "color",
        promptType: Manifest.Select,
        description: "Pick a color",
        default: "blue",
        options: colorOptions,
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      let msgs = getTestMessages()
      let capturedAnswers = switch result {
      | Ok(answers) => Some(Dict.get(answers, "color"))
      | Error(_) => None
      }
      let capturedCalls = callCount.contents
      mockIo.close()
      restoreConsoleLog()

      switch capturedAnswers {
      | Some(color) => {
          assert_eq(capturedCalls, 1)
          assert_eq(color, Some("blue"))
          assert_eq(Array.length(msgs), 0)
        }
      | None => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })

  // --- MultiSelect retry on zero-valid + warning on partial-invalid (3.4) ---

  testAsync("resolve: MultiSelect re-prompts on zero-valid and warns on partial-invalid", resolve => {
    installConsoleLogSpy()
    resetTestMessages()
    let (mockIo, callCount) = makeCountingIo(["x, y", "1, x"])
    let prompts: array<Manifest.prompt> = [
      {
        name: "colors",
        promptType: Manifest.MultiSelect,
        description: "Select colors",
        options: [
          {label: "Red", value: "red"},
          {label: "Green", value: "green"},
          {label: "Blue", value: "blue"},
        ],
      },
    ]
    let baseContext: dict<string> = Dict.make()

    PromptResolver.resolve(~io=mockIo, ~prompts, ~force=false, ~baseContext)
    ->Promise.then(result => {
      let msgs = getTestMessages()
      let capturedAnswers = switch result {
      | Ok(answers) => Some(Dict.get(answers, "colors"))
      | Error(_) => None
      }
      let capturedCalls = callCount.contents
      mockIo.close()
      restoreConsoleLog()

      switch capturedAnswers {
      | Some(colors) => {
          assert_eq(capturedCalls, 2)
          assert_eq(colors, Some("red"))
          assert_eq(Array.length(msgs), 2)
          switch msgs[0] {
          | Some(m) => assert_eq(m, "Error: No valid selections; enter numbers from the list")
          | None => assert_false(true)
          }
          switch msgs[1] {
          | Some(m) => assert_eq(m, "Warning: ignoring invalid entries: x")
          | None => assert_false(true)
          }
        }
      | None => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })
    ->ignore
  })
})
