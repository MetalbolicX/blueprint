// Expression — EJS template evaluation with declarative context
// Mirrors Go version's phase0/prompt_resolver.go expression evaluation

// Error types for resolver failures
type resolveError =
  | EvaluationError({prompt: string, field: string, message: string})
  | ValidationConfigError({prompt: string, message: string})
  | MissingOptionsError({prompt: string, message: string})

type resolutionStrategy = Force | Interactive

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

// Build evaluation context dict for EJS: {context: baseContext, answers: accumulatedAnswers}
let _buildEvalContext: (
  ~baseContext: dict<string>,
  ~answers: dict<string>,
) => {..} = (~baseContext, ~answers) => {
  {"context": baseContext, "answers": answers}
}

// Evaluate an EJS template string against evaluation context
// Returns Error on unsafe tags or EJS evaluation failure
let evalTemplate: (
  string,
  ~ctx: {..},
) => result<string, resolveError> = (template, ~ctx) => {
  if EjsSafety._hasUnsafeEjsTags(template) {
    Error(
      EvaluationError({
        prompt: "",
        field: "template",
        message: "Non-output EJS tags are not allowed; only <%= ... %> is permitted",
      }),
    )
  } else {
    try {
      let rendered = EjsSafety._renderEval(template, ctx)
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
