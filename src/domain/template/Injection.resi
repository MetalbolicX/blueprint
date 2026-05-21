type applyResult = {
  content: string,
  applied: bool,
}

let injectRegex: (string, string, string) => result<string, string>
let insertAfter: (string, string, string) => result<string, string>
let insertBefore: (string, string, string) => result<string, string>
let insertAtLine: (string, int, string) => result<string, string>
let shouldSkip: (string, string) => result<bool, string>
let trimTrailingNewline: string => string
let prependToContent: (string, string) => string
let appendToContent: (string, string) => string

let apply: (
  ~existingContent: string,
  ~renderedContent: string,
  ~directive: Template.directive,
  ~allDirectives: array<Template.directive>=?,
) => result<applyResult, string>
