// PromptResolver — re-export interface for backward compatibility

type resolveError = Expression.resolveError

let evalTemplate: (~ejs: Ports.ejs, string, ~ctx: {..}) => result<string, resolveError>
let _validateSelectInput: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
  ~default: string,
) => result<string, string>

let _tokenizeMultiSelect: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
) => (array<string>, array<string>)

let resolve: (
  ~io: Ports.interactiveIO,
  ~ejs: Ports.ejs,
  ~prompts: array<Manifest.prompt>,
  ~force: bool,
  ~baseContext: dict<string>,
) => promise<result<dict<string>, resolveError>>
