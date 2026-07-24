// Resolver — prompt orchestration and state machine
// Mirrors Go version's phase0/prompt_resolver.go main orchestrator

// processPromptBody: handles Force vs Interactive mode
// Force returns immediately, Interactive calls askPromptWithRetry
// Threads promptState; Force sets value directly, Interactive threads state to askPromptWithRetry.
let processPromptBody: Interactive.promptState => promise<result<Interactive.promptState, Expression.resolveError>> = state => {
  switch state.strategy {
  | Expression.Force => {
      switch Expression._requireOptions(state.prompt) {
      | Error(e) => Promise.resolve(Error(e))
      | Ok() =>
        switch state.prompt.default {
        | Some(defaultExpr) =>
          switch Expression._evaluateDefault(~defaultExpr, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
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
  | Expression.Interactive => {
      switch Expression._requireOptions(state.prompt) {
      | Error(e) => Promise.resolve(Error(e))
      | Ok() =>
        let defaultResult = switch state.prompt.default {
        | Some(defaultExpr) =>
          switch Expression._evaluateDefault(~defaultExpr, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
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
            switch Expression._evaluateOptions(~opts, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
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
              switch Validation._compilePattern(~pattern=v.pattern, ~promptName=state.prompt.name) {
              | Ok(re) => Ok(Some((re, v.message)))
              | Error(e) => Error(e)
              }
            | None => Ok(None)
            }

            switch patternResult {
            | Error(e) => Promise.resolve(Error(e))
            | Ok(compiledPattern) =>
              Interactive.askPromptWithRetry({
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
let processPrompt: Interactive.promptState => promise<result<Interactive.promptState, Expression.resolveError>> = state => {
  switch state.prompt.when_ {
  | Some(whenExpr) =>
    switch Expression._evaluateWhen(~whenExpr, ~promptName=state.prompt.name, ~baseContext=state.baseContext, ~answers=state.answers) {
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
) => promise<result<dict<string>, Expression.resolveError>> = (~io, ~prompts, ~force, ~baseContext) => {
  let answers = Dict.make()
  let strategy: Expression.resolutionStrategy = force ? Expression.Force : Expression.Interactive
  let idx = ref(0)

  let rec loop = () => {
    if idx.contents >= Array.length(prompts) {
      Promise.resolve(Ok(answers))
    } else {
      switch prompts[idx.contents] {
      | Some(prompt) =>
        let state: Interactive.promptState = {
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
