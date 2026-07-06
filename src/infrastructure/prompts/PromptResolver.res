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
  switch prompt.promptType {
  | Manifest.Select | Manifest.MultiSelect =>
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
  | _ => Ok()
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

        io.ask(fullQuestion)->Promise.then(answer => {
          let trimmedAnswer = String.trim(answer)
          let idx = switch Int.fromString(trimmedAnswer) {
          | Some(n) => n - 1
          | None => 0
          }
          let selected = switch opts[idx] {
          | Some(s) => s.value
          | None => ""
          }
          Promise.resolve(selected)
        })
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

        io.ask(fullQuestion)->Promise.then(answer => {
          let trimmed = String.trim(answer)
          if trimmed == "" {
            Promise.resolve("")
          } else {
            let parts = String.split(trimmed, ",")
            let selected =
              parts
              ->Array.map(s => String.trim(s))
              ->Array.map(s =>
                switch Int.fromString(s) {
                | Some(n) => {
                    let idx = n - 1
                    if idx >= 0 && idx < Array.length(opts) {
                      switch opts[idx] {
                      | Some(opt) => opt.value
                      | None => ""
                      }
                    } else {
                      ""
                    }
                  }
                | None => ""
                }
              )
              ->Array.filter(v => v != "")
              ->Array.join(",")
            Promise.resolve(selected)
          }
        })
      }
    | _ => io.ask(questionText)
    }
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

  if force {
    // Force mode: evaluate when/default, skip interactive I/O
    let rec forceLoop = (idx, prompts) => {
      if idx >= Array.length(prompts) {
        Promise.resolve(Ok(answers))
      } else {
        switch prompts[idx] {
        | Some(prompt) =>
          // Evaluate `when` — skip if false
          switch (prompt: Manifest.prompt).when_ {
          | Some(whenExpr) =>
            switch _evaluateWhen(~whenExpr, ~promptName=prompt.name, ~baseContext, ~answers) {
            | Ok(false) => forceLoop(idx + 1, prompts)
            | Ok(true) => assignForceDefault(prompt, prompts, idx)
            | Error(e) => Promise.resolve(Error(e))
            }
          | None => assignForceDefault(prompt, prompts, idx)
          }
        | None => Promise.resolve(Ok(answers))
        }
      }
    }
    and assignForceDefault = (prompt, prompts, idx) => {
      // Fail closed: Select/MultiSelect prompts without options can't be
      // answered by force-defaulting — that's the whole point of select.
      switch _requireOptions(prompt) {
      | Error(e) => Promise.resolve(Error(e))
      | Ok() =>
        switch prompt.default {
        | Some(defaultExpr) =>
          switch _evaluateDefault(~defaultExpr, ~promptName=prompt.name, ~baseContext, ~answers) {
          | Ok(d) => {
              Dict.set(answers, prompt.name, d)
              forceLoop(idx + 1, prompts)
            }
          | Error(e) => Promise.resolve(Error(e))
          }
        | None => {
            Dict.set(answers, prompt.name, "")
            forceLoop(idx + 1, prompts)
          }
        }
      }
    }

    forceLoop(0, prompts)
  } else {
    // Interactive mode — ask each prompt with evaluation
    let rec interactiveLoop = (idx, prompts) => {
      if idx >= Array.length(prompts) {
        Promise.resolve(Ok(answers))
      } else {
        switch prompts[idx] {
        | Some(prompt) =>
          // Evaluate `when` — skip if false
          switch (prompt: Manifest.prompt).when_ {
          | Some(whenExpr) =>
            switch _evaluateWhen(~whenExpr, ~promptName=prompt.name, ~baseContext, ~answers) {
            | Ok(false) => interactiveLoop(idx + 1, prompts)
            | Ok(true) => handleInteractivePrompt(prompt, prompts, idx)
            | Error(e) => Promise.resolve(Error(e))
            }
          | None => handleInteractivePrompt(prompt, prompts, idx)
          }
        | None => Promise.resolve(Ok(answers))
        }
      }
    }
    and handleInteractivePrompt = (prompt, prompts, idx) => {
      // Fail closed: Select/MultiSelect prompts without options can't be
      // answered interactively — never fall through to a free-text path.
      switch _requireOptions(prompt) {
      | Error(e) => Promise.resolve(Error(e))
      | Ok() =>
        // Evaluate default
        let defaultResult = switch prompt.default {
        | Some(defaultExpr) =>
          switch _evaluateDefault(~defaultExpr, ~promptName=prompt.name, ~baseContext, ~answers) {
          | Ok(d) => Ok(Some(d))
          | Error(e) => Error(e)
          }
        | None => Ok(None)
        }

        switch defaultResult {
        | Error(e) => Promise.resolve(Error(e))
        | Ok(evaluatedDefault) =>
          // Evaluate options for select prompts
          let optionsResult = switch prompt.options {
          | Some(opts) =>
            switch _evaluateOptions(~opts, ~promptName=prompt.name, ~baseContext, ~answers) {
            | Ok(eo) => Ok(Some(eo))
            | Error(e) => Error(e)
            }
          | None => Ok(None)
          }

          switch optionsResult {
          | Error(e) => Promise.resolve(Error(e))
          | Ok(evaluatedOptions) =>
            // Compile validation pattern once (if present)
            let patternResult = switch prompt.validate {
            | Some(v) =>
              switch _compilePattern(~pattern=v.pattern, ~promptName=prompt.name) {
              | Ok(re) => Ok(Some((re, v.message)))
              | Error(e) => Error(e)
              }
            | None => Ok(None)
            }

            switch patternResult {
            | Error(e) => Promise.resolve(Error(e))
            | Ok(compiledPattern) =>
              // Ask and validate with retry loop
              promptWithRetry(
                ~io,
                ~prompt,
                ~evaluatedDefault,
                ~evaluatedOptions,
                ~compiledPattern,
                ~prompts,
                ~idx,
              )
          }
        }
      }
      }
    }
    and promptWithRetry = (
      ~io,
      ~prompt,
      ~evaluatedDefault,
      ~evaluatedOptions,
      ~compiledPattern,
      ~prompts,
      ~idx,
    ) => {
      askPrompt(~io, ~prompt, ~evaluatedDefault, ~evaluatedOptions)->Promise.then(answer => {
        let finalAnswer = if String.trim(answer) == "" {
          evaluatedDefault->Option.getOr(prompt.default->Option.getOr(""))
        } else {
          answer
        }

        // Validate
        switch compiledPattern {
        | Some((re, errMsg)) =>
          if _matchesPattern(finalAnswer, re) {
            Dict.set(answers, prompt.name, finalAnswer)
            interactiveLoop(idx + 1, prompts)
          } else {
            // Show error message and retry
            Console.log("Error: " ++ errMsg)
            promptWithRetry(
              ~io,
              ~prompt,
              ~evaluatedDefault,
              ~evaluatedOptions,
              ~compiledPattern,
              ~prompts,
              ~idx,
            )
          }
        | None =>
          Dict.set(answers, prompt.name, finalAnswer)
          interactiveLoop(idx + 1, prompts)
        }
      })
    }

    interactiveLoop(0, prompts)
  }
}

// Readline interface lifecycle
let _createReadline: unit => NodeJs.Readline.readlineInterface = () => {
  NodeJs.Readline.createInterface(~input=NodeJs.Readline.stdin, ~output=NodeJs.Readline.stdout, ())
}

let _closeReadline: NodeJs.Readline.readlineInterface => unit = rl => {
  rl.close()
}
