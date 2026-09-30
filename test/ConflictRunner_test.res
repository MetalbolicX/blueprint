// ConflictRunner_test — interactive conflict-resolution behavior

open TestHelpers

let mockIo = (answers: array<string>, prompts: ref<array<string>>): Ports.interactiveIO => {
  let index = ref(0)
  {
    ask: prompt => {
      prompts.contents->Array.push(prompt)->ignore
      let answer = switch answers[index.contents] {
      | Some(answer) => answer
      | None => ""
      }
      index.contents = index.contents + 1
      Promise.resolve(answer)
    },
    askConfirm: (~question as _, ~defaultYes as _=?) => Promise.resolve(true),
    close: () => (),
  }
}

let conflicts = [
  {
    ConflictResolver.sourcePath: "src",
    targetPath: "tgt",
  },
]

suite("ConflictRunner", () => {
  testAsync("prompt contract maps advertised keys to stated semantics", resolve => {
    assert_eq(ConflictResolver.parseChoice("y"), Some(ConflictResolver.Yes))
    assert_eq(ConflictResolver.parseChoice("n"), Some(ConflictResolver.NoAll))
    assert_eq(ConflictResolver.parseChoice("s"), Some(ConflictResolver.Select))
    assert_eq(ConflictResolver.parseChoice("a"), Some(ConflictResolver.Abort))
    assert_eq(ConflictResolver.parseChoice("all"), Some(ConflictResolver.YesAll))

    let prompts = ref([])
    let io = mockIo(["abort"], prompts)
    ConflictRunner.resolveConflicts(~io, ~conflicts, ~force=false)->Promise.then(result => {
      let prompt = switch prompts.contents[0] {
      | Some(text) => text
      | None => ""
      }
      assert_true(String.includes(prompt, "[y]es / [n]o / [s]elect / [a]bort"))
      assert_true(String.includes(prompt, "all to overwrite everything"))
      assert_true(String.includes(prompt, "a or abort stops with nothing written"))
      switch result {
      | Error(message) => assert_eq(message, "Aborted by user")
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("select mode re-prompts with feedback for unrecognized input", resolve => {
    let prompts = ref([])
    let io = mockIo(["s", "invalid", "y"], prompts)

    ConflictRunner.resolveConflicts(~io, ~conflicts, ~force=false)->Promise.then(result => {
      assert_eq(Array.length(prompts.contents), 3)
      let feedback = switch prompts.contents[2] {
      | Some(text) => text
      | None => ""
      }
      assert_true(String.includes(feedback, "Invalid"))
      switch result {
      | Ok(decisions) => {
          let overwrite = switch decisions[0] {
          | Some(decision) => decision.overwrite
          | None => false
          }
          assert_true(overwrite)
        }
      | Error(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })->ignore
  })

  testAsync("select mode abort stops the whole run", resolve => {
    let prompts = ref([])
    let io = mockIo(["s", "abort"], prompts)

    ConflictRunner.resolveConflicts(~io, ~conflicts, ~force=false)->Promise.then(result => {
      assert_eq(Array.length(prompts.contents), 2)
      switch result {
      | Error(message) => assert_eq(message, "Aborted by user")
      | Ok(_) => assert_false(true)
      }
      resolve()
      Promise.resolve()
    })->ignore
  })
})
