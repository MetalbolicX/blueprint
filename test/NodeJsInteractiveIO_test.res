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
