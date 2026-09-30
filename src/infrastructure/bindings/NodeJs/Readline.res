/**
 * Node.js readline bindings — interactive line reading
 */

type interface = {
  question: string => promise<string>,
  close: unit => unit,
}

type completer = (string, int) => promise<(array<string>, int)>

type readlineInterface = {
  question: (string, ~completer: completer=?) => promise<string>,
  close: unit => unit,
}

type pendingQuestion = {
  resolve: string => unit,
  reject: exn => unit,
}

type nativeInterface = {
  setPrompt: string => unit,
  prompt: unit => unit,
  close: unit => unit,
  on: (string, string => unit) => unit,
}

type streamReadable
type streamWritable

@new external makeError: string => exn = "Error"

@module("node:process") external stdin: streamReadable = "stdin"
@module("node:process") external stdout: streamWritable = "stdout"

@module("node:readline")
external createNativeInterface: (
  ~input: streamReadable,
  ~output: streamWritable=?,
  unit,
) => nativeInterface = "createInterface"

let createInterface = (~input, ~output=?, ()) => {
  let native = createNativeInterface(~input, ~output?, ())
  let closed = ref(false)
  let answers: ref<array<string>> = ref([])
  let pending: ref<array<pendingQuestion>> = ref([])

  native.on("line", answer => {
    switch pending.contents->Array.shift {
    | Some(question) => question.resolve(answer)
    | None => answers := answers.contents->Array.concat([answer])
    }
  })
  native.on("close", _ => {
    closed := true
    pending.contents->Array.forEach(question =>
      question.reject(makeError("input ended before an answer was provided"))
    )
    pending := []
  })

  {
    question: (question, ~completer as _completer=?) => {
      switch answers.contents->Array.shift {
      | Some(answer) => Promise.resolve(answer)
      | None if closed.contents =>
        Promise.reject(makeError("input ended before an answer was provided"))
      | None =>
        native.setPrompt(question)
        native.prompt()
        Promise.make((resolve, reject) => {
          pending := pending.contents->Array.concat([{resolve, reject}])
        })
      }
    },
    close: () => native.close(),
  }
}
