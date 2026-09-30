open TestHelpers

let setMockAnswers: array<string> => unit = %raw(`
  function(answers) {
    global.__mockAnswers = answers;
  }
`)

let mockCreateInterface: (
  ~input: Bindings.NodeJs.Readline.streamReadable,
  ~output: Bindings.NodeJs.Readline.streamWritable=?,
  unit,
) => Bindings.NodeJs.Readline.readlineInterface = %raw(`
  function(input, output) {
    return {
      question: (q) => {
        return new Promise(resolve => {
          const nextAnswer = global.__mockAnswers.shift() || "";
          resolve(nextAnswer);
        });
      },
      close: () => {}
    };
  }
`)

suite("NodeJsInteractiveIO adapter", () => {
  testAsync("ask opens the readline interface lazily", resolve => {
    let createCalls = ref(0)
    let create: (
      ~input: Bindings.NodeJs.Readline.streamReadable,
      ~output: Bindings.NodeJs.Readline.streamWritable=?,
      unit,
    ) => Bindings.NodeJs.Readline.readlineInterface = (~input, ~output=?, ()) => {
      createCalls.contents = createCalls.contents + 1
      mockCreateInterface(~input, ~output?, ())
    }
    let io = NodeJsInteractiveIO.make(~createInterface=create, ())
    assert_eq(createCalls.contents, 0)
    io.close()
    assert_eq(createCalls.contents, 0)
    setMockAnswers(["Alice"])
    let _ = (async () => {
      let answer = await io.ask("Name: ")
      assert_eq(answer, "Alice")
      assert_eq(createCalls.contents, 1)
      io.close()
      io.close()
      resolve()
    })()
  })

  testAsync("ask rejects when readline closes while waiting for input", resolve => {
    let rejectQuestion: ref<option<exn => unit>> = ref(None)
    let create: (
      ~input: Bindings.NodeJs.Readline.streamReadable,
      ~output: Bindings.NodeJs.Readline.streamWritable=?,
      unit,
    ) => Bindings.NodeJs.Readline.readlineInterface = (~input as _input, ~output as _output=?, ()) => {
      {
        question: (_, ~completer as _completer=?) => Promise.make((_, reject) => rejectQuestion := Some(reject)),
        close: () => {
          switch rejectQuestion.contents {
          | Some(reject) => reject(Obj.magic("input ended before an answer was provided"))
          | None => ()
          }
        },
      }
    }
    let io = NodeJsInteractiveIO.make(~createInterface=create, ())
    let _ = (async () => {
      let question = io.ask("Name: ")
      io.close()
      io.close()
      let rejected = try {
        let _ = await question
        false
      } catch {
      | _ => true
      }
      assert_true(rejected)
      resolve()
    })()
  })

  testAsync("ask returns the user input", resolve => {
    let _ = (async () => {
      setMockAnswers(["Alice"])
      let io = NodeJsInteractiveIO.make(~createInterface=mockCreateInterface, ())
      
      let answer = await io.ask("What is your name? ")
      assert_eq(answer, "Alice")
      
      resolve()
    })()
  })

  testAsync("askConfirm returns true for 'y'", resolve => {
    let _ = (async () => {
      setMockAnswers(["y"])
      let io = NodeJsInteractiveIO.make(~createInterface=mockCreateInterface, ())
      
      let answer = await io.askConfirm(~question="Are you sure?", ~defaultYes=false)
      assert_true(answer)
      
      resolve()
    })()
  })

  testAsync("askConfirm returns false for 'n'", resolve => {
    let _ = (async () => {
      setMockAnswers(["n"])
      let io = NodeJsInteractiveIO.make(~createInterface=mockCreateInterface, ())
      
      let answer = await io.askConfirm(~question="Are you sure?", ~defaultYes=true)
      assert_true(!answer)
      
      resolve()
    })()
  })

  testAsync("askConfirm uses defaultYes when input is empty", resolve => {
    let _ = (async () => {
      setMockAnswers(["", ""])
      let io = NodeJsInteractiveIO.make(~createInterface=mockCreateInterface, ())
      
      let answer1 = await io.askConfirm(~question="Are you sure?", ~defaultYes=true)
      assert_true(answer1)
      
      let answer2 = await io.askConfirm(~question="Are you sure?", ~defaultYes=false)
      assert_true(!answer2)
      
      resolve()
    })()
  })

  testAsync("askConfirm handles whitespace", resolve => {
    let _ = (async () => {
      setMockAnswers(["  yes  "])
      let io = NodeJsInteractiveIO.make(~createInterface=mockCreateInterface, ())
      
      let answer = await io.askConfirm(~question="Are you sure?", ~defaultYes=false)
      assert_true(answer)
      
      resolve()
    })()
  })

  testAsync("askConfirm handles uppercase", resolve => {
    let _ = (async () => {
      setMockAnswers(["N"])
      let io = NodeJsInteractiveIO.make(~createInterface=mockCreateInterface, ())
      
      let answer = await io.askConfirm(~question="Are you sure?", ~defaultYes=true)
      assert_true(!answer)
      
      resolve()
    })()
  })
})
