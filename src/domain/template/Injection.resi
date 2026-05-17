type applyResult = {
  content: string,
  applied: bool,
}

let injectRegex: (string, string, string) => result<string, string>
let insertAfter: (string, string, string) => result<string, string>
let insertBefore: (string, string, string) => result<string, string>
let prependToContent: (string, string) => string
let appendToContent: (string, string) => string

let apply: (
  ~existingContent: string,
  ~renderedContent: string,
  ~directive: Template.directive,
) => result<applyResult, string>
