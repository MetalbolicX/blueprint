type resolveError =
  | EvaluationError({prompt: string, field: string, message: string})
  | ValidationConfigError({prompt: string, message: string})
  | MissingOptionsError({prompt: string, message: string})

let evalTemplate: (string, ~ctx: {..}) => result<string, resolveError>

let resolve: (
  ~io: Ports.interactiveIO,
  ~prompts: array<Manifest.prompt>,
  ~force: bool,
  ~baseContext: dict<string>,
) => promise<result<dict<string>, resolveError>>
