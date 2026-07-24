// PromptResolver — interactive prompt resolution via node:readline
// Supports input, select, and confirm prompt types with declarative evaluation
// Mirrors Go version's phase0/prompt_resolver.go

// Error types for resolver failures
type resolveError =
  | EvaluationError({prompt: string, field: string, message: string})
  | ValidationConfigError({prompt: string, message: string})
  | MissingOptionsError({prompt: string, message: string})

// Select/MultiSelect prompts must have options configured before they can be
// asked or have a default applied. Returning Error here means we fail closed
// instead of degrading to a free-text fallback path that would be meaningless
// for a select-style prompt.
let _requireOptions: Manifest.prompt => result<unit, resolveError> = prompt => {
  if Manifest.promptRequiresOptions(prompt.promptType) {
    switch prompt.options {
    | Some(opts) if Array.length(opts) > 0 => Ok()
    | _ =>
      Error(
        MissingOptionsError({
          prompt: prompt.name,
          message: "select prompt requires options",
        }),
      )
    }
  } else {
    Ok()
  }
}

// --- EJS expression safety guard ---

// Check that a template contains only interpolation tags (<%= ... %>)
// Rejects control flow (<% ... %>) and unescaped output (<%- ... %>)
let _hasUnsafeEjsTags: string => bool = template => {
  // Match any <% that is NOT followed by =
  let controlFlowPattern = RegExp.fromString("<%(?![-=])")
  // Match <%- (unescaped output)
  let unescapedPattern = RegExp.fromString("<%-")
  RegExp.test(controlFlowPattern, template) || RegExp.test(unescapedPattern, template)
}

// EJS render wrapper: Ejs.render is typed as `dict<string>`, but our eval
// context is a structured object ({context: dict<string>, answers: dict<string>}).
// This helper localises the cast in one named place so the unsafe boundary is
// explicit and reviewable.
let _renderEval: (string, {..}) => string = (template, ctx) => {
  Ejs.render(template, ctx->Obj.magic)
}

// Evaluate an EJS template string against evaluation context
// Returns Error on unsafe tags or EJS evaluation failure
let evalTemplate: (
  string,
  ~ctx: {..},
) => result<string, resolveError> = (template, ~ctx) => {
  if _hasUnsafeEjsTags(template) {
    Error(
      EvaluationError({
        prompt: "",
        field: "template",
        message: "Non-output EJS tags are not allowed; only <%= ... %> is permitted",
      }),
    )
  } else {
    try {
      let rendered = _renderEval(template, ctx)
      Ok(rendered)
    } catch {
    | JsExn(obj) =>
      let msg = JsExn.message(obj)->Option.getOr("EJS evaluation failed")
      Error(
        EvaluationError({
          prompt: "",
          field: "template",
          message: msg,
        }),
      )
    }
  }
}

// Build evaluation context dict for EJS: {context: baseContext, answers: accumulatedAnswers}
let _buildEvalContext: (
  ~baseContext: dict<string>,
  ~answers: dict<string>,
) => {..} = (~baseContext, ~answers) => {
  {"context": baseContext, "answers": answers}
}

// --- Conditional evaluation ---

// Evaluate `when` expression; returns true if prompt should be shown
let _evaluateWhen: (
  ~whenExpr: string,
  ~promptName: string,
  ~baseContext: dict<string>,
  ~answers: dict<string>,
) => result<bool, resolveError> = (~whenExpr, ~promptName, ~baseContext, ~answers) => {
  let evalCtx = _buildEvalContext(~baseContext, ~answers)
  switch evalTemplate(whenExpr, ~ctx=evalCtx) {
  | Ok(rendered) => {
      let trimmed = String.trim(rendered)->String.toLowerCase
      Ok(trimmed != "false" && trimmed != "" && trimmed != "0")
    }
  | Error(EvaluationError(e)) =>
    Error(EvaluationError({...e, prompt: promptName, field: "when"}))
  | Error(err) => Error(err)
  }
}

// --- Default evaluation ---

// Evaluate `default` template string
let _evaluateDefault: (
  ~defaultExpr: string,
  ~promptName: string,
  ~baseContext: dict<string>,
  ~answers: dict<string>,
) => result<string, resolveError> = (~defaultExpr, ~promptName, ~baseContext, ~answers) => {
  let evalCtx = _buildEvalContext(~baseContext, ~answers)
  switch evalTemplate(defaultExpr, ~ctx=evalCtx) {
  | Ok(rendered) => Ok(rendered)
  | Error(EvaluationError(e)) =>
    Error(EvaluationError({...e, prompt: promptName, field: "default"}))
  | Error(err) => Error(err)
  }
}

// --- Options evaluation ---

// Evaluate select options templates (label/value)
let _evaluateOptions: (
  ~opts: array<Manifest.promptOption>,
  ~promptName: string,
  ~baseContext: dict<string>,
  ~answers: dict<string>,
) => result<array<Manifest.promptOption>, resolveError> = (
  ~opts,
  ~promptName,
  ~baseContext,
  ~answers,
) => {
  let evalCtx = _buildEvalContext(~baseContext, ~answers)
  let results: array<option<Manifest.promptOption>> =
    opts->Array.map(opt => {
      let labelResult = evalTemplate(opt.label, ~ctx=evalCtx)
      let valueResult = evalTemplate(opt.value, ~ctx=evalCtx)
      switch (labelResult, valueResult) {
      | (Ok(l), Ok(v)) => Some({Manifest.label: l, value: v})
      | _ => None
      }
    })
  let filtered = results->Array.filterMap(x => x)
  if Array.length(filtered) == Array.length(opts) {
    Ok(filtered)
  } else {
    Error(
      EvaluationError({
        prompt: promptName,
        field: "options",
        message: "Failed to evaluate option templates",
      }),
    )
  }
}

// --- Pure validation helpers (no I/O) ---

// Validate a raw answer against a numbered Select option list.
// Returns Ok(value) on a valid numeric selection, Ok(default) on empty
// input (so the caller can preserve default behavior without re-prompting),
// or Error(msg) on non-numeric / out-of-range input.
let _validateSelectInput: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
  ~default: string,
) => result<string, string> = (~answer, ~opts, ~default) => {
  let trimmed = String.trim(answer)
  if trimmed == "" {
    Ok(default)
  } else {
    switch Int.fromString(trimmed) {
    | None => Error("Please enter a number")
    | Some(n) =>
      switch opts[n - 1] {
      | Some(opt) => Ok(opt.value)
      | None => {
          let max = Int.toString(Array.length(opts))
          Error("Please enter a number between 1 and " ++ max)
        }
      }
    }
  }
}

// Split a comma-separated answer into (validValues, invalidTokens).
// Valid values are the option values whose numeric index is in range;
// invalid tokens are the original trimmed strings that did not resolve.
let _tokenizeMultiSelect: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
) => (array<string>, array<string>) = (~answer, ~opts) => {
  let initial: (array<string>, array<string>) = ([], [])
  String.split(answer, ",")
  ->Array.map(s => String.trim(s))
  ->Array.filter(s => s != "")
  ->Array.reduce(initial, (acc, token) => {
    let (valid, invalid) = acc
    switch Int.fromString(token) {
    | Some(n) =>
      switch opts[n - 1] {
      | Some(opt) => (Array.concat(valid, [opt.value]), invalid)
      | None => (valid, Array.concat(invalid, [token]))
      }
    | None => (valid, Array.concat(invalid, [token]))
    }
  })
}

// --- Validation ---

// Compile a regex pattern string, returning error on invalid syntax
let _compilePattern: (
  ~pattern: string,
  ~promptName: string,
) => result<RegExp.t, resolveError> = (~pattern, ~promptName) => {
  try {
    Ok(RegExp.fromString(pattern))
  } catch {
  | JsExn(obj) =>
    let msg = JsExn.message(obj)->Option.getOr("Invalid regex pattern")
    Error(
      ValidationConfigError({
        prompt: promptName,
        message: "Invalid validate.pattern: " ++ msg,
      }),
    )
  }
}

// Check if a value matches a compiled regex
let _matchesPattern: (string, RegExp.t) => bool = (value, re) => {
  RegExp.test(re, value)
}

// --- Ask a single question (interactive) ---

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
            switch _validateSelectInput(~answer, ~opts, ~default=defaultVal) {
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
              let (valid, invalid) = _tokenizeMultiSelect(~answer=trimmed, ~opts)
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

// --- Unified prompt processor ---

type resolutionStrategy = Force | Interactive

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
  strategy: resolutionStrategy,
}

// askPromptWithRetry: iterative retry loop (non-recursive at top level)
// Uses an inner recursive helper for the actual retry recursion.
// Threads promptState; mutates answers in place via Dict.set.
let askPromptWithRetry: promptState => promise<result<promptState, resolveError>> = state => {
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
        if _matchesPattern(finalAnswer, re) {
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

// processPromptBody: handles Force vs Interactive mode
// Force returns immediately, Interactive calls askPromptWithRetry
// Threads promptState; Force sets value directly, Interactive threads state to askPromptWithRetry.
let processPromptBody: promptState => promise<result<promptState, resolveError>> = state => {
  switch state.strategy {
  | Force => {
      switch _requireOptions(state.prompt) {
      | Error(e) => Promise.resolve(Error(e))
      | Ok() =>
        switch state.prompt.default {
        | Some(defaultExpr) =>
          switch _evaluateDefault(~defaultExpr, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
          | Ok(d) => {
              let answers = state.answers
              Dict.set(answers, state.prompt.name, d)
              Promise.resolve(Ok({...state, answers, value: Some(d)}))
            }
          | Error(e) => Promise.resolve(Error(e))
          }
        | None => {
            let answers = state.answers
            Dict.set(answers, state.prompt.name, "")
            Promise.resolve(Ok({...state, answers, value: Some("")}))
          }
        }
      }
    }
  | Interactive => {
      switch _requireOptions(state.prompt) {
      | Error(e) => Promise.resolve(Error(e))
      | Ok() =>
        let defaultResult = switch state.prompt.default {
        | Some(defaultExpr) =>
          switch _evaluateDefault(~defaultExpr, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
          | Ok(d) => Ok(Some(d))
          | Error(e) => Error(e)
          }
        | None => Ok(None)
        }

        switch defaultResult {
        | Error(e) => Promise.resolve(Error(e))
        | Ok(evaluatedDefault) =>
          let optionsResult = switch state.prompt.options {
          | Some(opts) =>
            switch _evaluateOptions(~opts, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
            | Ok(eo) => Ok(Some(eo))
            | Error(e) => Error(e)
            }
          | None => Ok(None)
          }

          switch optionsResult {
          | Error(e) => Promise.resolve(Error(e))
          | Ok(evaluatedOptions) =>
            let patternResult = switch state.prompt.validate {
            | Some(v) =>
              switch _compilePattern(~pattern=v.pattern, ~promptName=state.prompt.name) {
              | Ok(re) => Ok(Some((re, v.message)))
              | Error(e) => Error(e)
              }
            | None => Ok(None)
            }

            switch patternResult {
            | Error(e) => Promise.resolve(Error(e))
            | Ok(compiledPattern) =>
              askPromptWithRetry({
                ...state,
                evaluatedDefault,
                evaluatedOptions,
                compiledPattern,
                attempt: 0,
                lastError: None,
              })
            }
          }
        }
      }
    }
  }
}

// processPrompt: top-level per-prompt processor — evaluates `when` then delegates
// Threads promptState through the evaluation and into processPromptBody.
let processPrompt: promptState => promise<result<promptState, resolveError>> = state => {
  switch state.prompt.when_ {
  | Some(whenExpr) =>
    switch _evaluateWhen(~whenExpr, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
    | Ok(false) => Promise.resolve(Ok(state))
    | Ok(true) => processPromptBody(state)
    | Error(e) => Promise.resolve(Error(e))
    }
  | None => processPromptBody(state)
  }
}

// --- Main resolve function ---

let resolve: (
  ~io: Ports.interactiveIO,
  ~prompts: array<Manifest.prompt>,
  ~force: bool,
  ~baseContext: dict<string>,
) => promise<result<dict<string>, resolveError>> = (~io, ~prompts, ~force, ~baseContext) => {
  let answers = Dict.make()
  let strategy = force ? Force : Interactive
  let idx = ref(0)

  let rec loop = () => {
    if idx.contents >= Array.length(prompts) {
      Promise.resolve(Ok(answers))
    } else {
      switch prompts[idx.contents] {
      | Some(prompt) =>
        let state: promptState = {
          prompt,
          io,
          baseContext,
          answers,
          evaluatedDefault: None,
          evaluatedOptions: None,
          compiledPattern: None,
          value: None,
          attempt: 0,
          lastError: None,
          strategy,
        }
        processPrompt(state)->Promise.then(result => {
          switch result {
          | Ok(_newState) =>
            idx.contents = idx.contents + 1
            loop()
          | Error(e) => Promise.resolve(Error(e))
          }
        })
      | None =>
        idx.contents = idx.contents + 1
        loop()
      }
    }
  }

  loop()
}
