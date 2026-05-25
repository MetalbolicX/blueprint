open TestHelpers

let setupMock: unit => unit = %raw(`
  function() {
    globalThis.prompt = (msg, def) => {
      if (msg.includes("Mock?")) return "mocked_answer";
      if (msg.includes("Yes?")) return "y";
      return null;
    }
  }
`)

let teardownMock: unit => unit = %raw(`
  function() {
    delete globalThis.prompt;
  }
`)

suite("DenoInteractiveIO adapter", () => {
  let io = DenoInteractiveIO.make()

  testAsync("ask returns answer", resolve => {
    setupMock()
    io.ask("Mock?")->Promise.then(ans => {
      assert_eq(ans, "mocked_answer")
      
      io.ask("Empty?")->Promise.then(emptyAns => {
        assert_eq(emptyAns, "")
        teardownMock()
        resolve()
        Promise.resolve()
      })->ignore
      
      Promise.resolve()
    })->ignore
  })
  
  testAsync("askConfirm returns answer", resolve => {
    setupMock()
    io.askConfirm(~question="Yes?")->Promise.then(ans => {
      assert_eq(ans, true)
      teardownMock()
      resolve()
      Promise.resolve()
    })->ignore
  })
})
