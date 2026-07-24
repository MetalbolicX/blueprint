// Interactive — interactive prompting with retry loop
// Mirrors Go version's phase0/prompt_resolver.go interactive prompting

// Threaded state record for the three-processPrompt trio.
// Replaces the 5-6 individual labelled parameters each function previously took.
type promptState = {
  prompt: Manifest.prompt,
  io: Ports.interactiveIO,
  baseContext: dict<string>,
  answers: dict<string>,
  evaluatedDefault: option<string>,
  evaluatedOptions: option<array<Manifest.promptOption>>,
  compiledPattern: option<(RegExp.t, string)>,
  value: option<string>,
  attempt: int,
  lastError: option<string>,
  strategy: Expression.resolutionStrategy,
}

// Ask a single question (interactive)
let askPrompt: (
  ~io: Ports.interactiveIO,
  ~prompt: Manifest.prompt,
  ~evaluatedDefault: option<string>,
  ~evaluatedOptions: option<array<Manifest.promptOption>>,
) => promise<string> = (~io, ~prompt, ~evaluatedDefault, ~evaluatedOptions) => {
  let displayDefault = evaluatedDefault->Option.getOr(prompt.default->Option.getOr(""))
  let questionText =
    prompt.description ++
    switch displayDefault {
    | d if d != "" => " [" ++ d ++ "]"
    | _ => ""
    } ++ ": "

  switch prompt.promptType {
  | Manifest.Input => io.ask(questionText)

  | Manifest.Select =>
    // Show numbered options using evaluated options if available
    let opts = switch evaluatedOptions {
    | Some(eo) if Array.length(eo) > 0 => Some(eo)
    | _ => prompt.options
    }
    switch opts {
    | Some(opts) if Array.length(opts) > 0 => {
        let optionsText =
          opts
          ->Array.mapWithIndex((opt, i) => {
            "  " ++ Int.toString(i + 1) ++ ". " ++ opt.label
          })
          ->Array.join("\n")

        let fullQuestion = optionsText ++ "\n" ++ questionText
        let defaultVal = evaluatedDefault->Option.getOr(prompt.default->Option.getOr(""))

        let rec selectLoop = () =>
          io.ask(fullQuestion)->Promise.then(answer => {
            switch Validation._validateSelectInput(~answer, ~opts, ~default=defaultVal) {
            | Ok(value) => Promise.resolve(value)
            | Error(msg) =>
              Console.log("Error: " ++ msg)
              selectLoop()
            }
          })
        selectLoop()
      }
    | _ => io.ask(questionText)
    }

  | Manifest.Confirm =>
    io.askConfirm(~question=questionText ++ " (y/n) ")->Promise.then(b => if b { Promise.resolve("true") } else { Promise.resolve("false") })

  | Manifest.MultiSelect =>
    let opts = switch evaluatedOptions {
    | Some(eo) if Array.length(eo) > 0 => Some(eo)
    | _ => prompt.options
    }
    switch opts {
    | Some(opts) if Array.length(opts) > 0 => {
        let optionsText =
          opts
          ->Array.mapWithIndex((opt, i) => {
            "  " ++ Int.toString(i + 1) ++ ". " ++ opt.label
          })
          ->Array.join("\n")

        let fullQuestion = optionsText ++ "\nEnter numbers separated by commas (e.g. 1,3,5): "

        let rec multiLoop = () =>
          io.ask(fullQuestion)->Promise.then(answer => {
            let trimmed = String.trim(answer)
            if trimmed == "" {
              Promise.resolve("")
            } else {
              let (valid, invalid) = Validation._tokenizeMultiSelect(~answer=trimmed, ~opts)
              if Array.length(valid) == 0 {
                Console.log("Error: No valid selections; enter numbers from the list")
                multiLoop()
              } else {
                if Array.length(invalid) > 0 {
                  let joinedInvalid = invalid->Array.join(", ")
                  Console.log("Warning: ignoring invalid entries: " ++ joinedInvalid)
                }
                Promise.resolve(valid->Array.join(","))
              }
            }
          })
        multiLoop()
      }
    | _ => io.ask(questionText)
    }
  }
}

// askPromptWithRetry: iterative retry loop (non-recursive at top level)
// Uses an inner recursive helper for the actual retry recursion.
// Threads promptState; mutates answers in place via Dict.set.
let askPromptWithRetry: promptState => promise<result<promptState, Expression.resolveError>> = state => {
  let rec loop = state => {
    askPrompt(
      ~io=state.io,
      ~prompt=state.prompt,
      ~evaluatedDefault=state.evaluatedDefault,
      ~evaluatedOptions=state.evaluatedOptions,
    )->Promise.then(answer => {
      let finalAnswer = if String.trim(answer) == "" {
        state.evaluatedDefault->Option.getOr(state.prompt.default->Option.getOr(""))
      } else {
        answer
      }

      switch state.compiledPattern {
      | Some((re, errMsg)) =>
        if Validation._matchesPattern(finalAnswer, re) {
          let answers = state.answers
          Dict.set(answers, state.prompt.name, finalAnswer)
          Promise.resolve(Ok({...state, answers, value: Some(finalAnswer)}))
        } else {
          Console.log("Error: " ++ errMsg)
          loop({...state, answers: state.answers, attempt: state.attempt + 1, lastError: Some(errMsg)})
        }
      | None =>
        let answers = state.answers
        Dict.set(answers, state.prompt.name, finalAnswer)
        Promise.resolve(Ok({...state, answers, value: Some(finalAnswer)}))
      }
    })
  }
  loop(state)
}
