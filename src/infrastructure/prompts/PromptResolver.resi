type resolveError =
  | EvaluationError({prompt: string, field: string, message: string})
  | ValidationConfigError({prompt: string, message: string})
  | MissingOptionsError({prompt: string, message: string})

let _validateSelectInput: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
  ~default: string,
) => result<string, string>

let _tokenizeMultiSelect: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
) => (array<string>, array<string>)

let evalTemplate: (string, ~ctx: {..}) => result<string, resolveError>

let resolve: (
  ~io: Ports.interactiveIO,
  ~prompts: array<Manifest.prompt>,
  ~force: bool,
  ~baseContext: dict<string>,
) => promise<result<dict<string>, resolveError>>
