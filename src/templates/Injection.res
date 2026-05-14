// File injection modes: inject, after, before, prepend, append
// Applies rendered content to existing target files

let injectRegex: (string, string, string) => result<string, string> = (content, pattern, replacement) => {
  try {
    let regex = Js.Re.fromString(pattern)
    let result = content->Js.String.replaceByRe(regex, replacement)
    Ok(result)
  } catch {
  | Js.Exn.Error(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let insertAfter: (string, string, string) => result<string, string> = (content, pattern, insertion) => {
  try {
    let regex = Js.Re.fromString(pattern)
    let result = content->Js.String.replaceByRe(regex, "$&" ++ insertion)
    Ok(result)
  } catch {
  | Js.Exn.Error(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let insertBefore: (string, string, string) => result<string, string> = (content, pattern, insertion) => {
  try {
    let regex = Js.Re.fromString(pattern)
    let result = content->Js.String.replaceByRe(regex, insertion ++ "$&")
    Ok(result)
  } catch {
  | Js.Exn.Error(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let prependToContent: (string, string) => string = (content, prepend) => {
  prepend ++ "\n" ++ content
}

let appendToContent: (string, string) => string = (content, append) => {
  content ++ "\n" ++ append
}

// Apply injection based on directive type
type applyResult = {
  content: string,
  applied: bool,
}

let apply: (
  ~existingContent: string,
  ~renderedContent: string,
  ~directive: Template.directive,
) => result<applyResult, string> = (~existingContent, ~renderedContent, ~directive) => {
  switch directive {
  | Inject(pattern) => {
    let result = injectRegex(existingContent, pattern, renderedContent)
    result->Result.map(content => { content: content, applied: true })
  }
  | After(pattern) => {
    let result = insertAfter(existingContent, pattern, renderedContent)
    result->Result.map(content => { content: content, applied: true })
  }
  | Before(pattern) => {
    let result = insertBefore(existingContent, pattern, renderedContent)
    result->Result.map(content => { content: content, applied: true })
  }
  | Prepend => Ok({ content: prependToContent(existingContent, renderedContent), applied: true })
  | Append => Ok({ content: appendToContent(existingContent, renderedContent), applied: true })
  | _ => Ok({ content: existingContent, applied: false })  // non-injection directives
  }
}