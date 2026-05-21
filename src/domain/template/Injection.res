// File injection modes: inject, after, before, prepend, append
// Applies rendered content to existing target files

let injectRegex: (string, string, string) => result<string, string> = (
  content,
  pattern,
  replacement,
) => {
  try {
    let regex = RegExp.fromString(pattern)
    let result = Js.String.replaceByRe(regex, replacement, content)
    Ok(result)
  } catch {
  | JsExn(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let insertAfter: (string, string, string) => result<string, string> = (
  content,
  pattern,
  insertion,
) => {
  try {
    let regex = RegExp.fromString(pattern)
    let result = Js.String.replaceByRe(regex, "$&" ++ insertion, content)
    Ok(result)
  } catch {
  | JsExn(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let insertBefore: (string, string, string) => result<string, string> = (
  content,
  pattern,
  insertion,
) => {
  try {
    let regex = RegExp.fromString(pattern)
    let result = Js.String.replaceByRe(regex, insertion ++ "$&", content)
    Ok(result)
  } catch {
  | JsExn(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let insertAtLine: (string, int, string) => result<string, string> = (
  content,
  line,
  insertion,
) => {
  if line < 1 {
    Error("Line number must be >= 1")
  } else {
    let lines = Js.String.split("\n", content)
    let idx = line - 1
    if idx > Array.length(lines) {
      Error("Line number out of range")
    } else {
      let before = lines->Array.slice(~start=0, ~end=idx)
      let after = lines->Array.slice(~start=idx)
      let merged = Array.concat(Array.concat(before, [insertion]), after)
      Ok(Array.join(merged, "\n"))
    }
  }
}

let shouldSkip: (string, string) => result<bool, string> = (content, pattern) => {
  try {
    let regex = RegExp.fromString(pattern)
    Ok(regex->RegExp.test(content))
  } catch {
  | JsExn(_) => Error("Invalid regex pattern: " ++ pattern)
  }
}

let trimTrailingNewline: string => string = content => {
  if Js.String.endsWith("\n", content) {
    String.slice(content, ~start=0, ~end=String.length(content) - 1)
  } else {
    content
  }
}

let prependToContent: (string, string) => string = (content, prepend) => {
  prepend ++ "\n\n" ++ content
}

let appendToContent: (string, string) => string = (content, append) => {
  content ++ "\n\n" ++ append
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
  ~allDirectives: array<Template.directive>=?,
) => result<applyResult, string> = (~existingContent, ~renderedContent, ~directive, ~allDirectives=?) => {
  let effectiveRendered = switch allDirectives {
  | Some(ds) if ds->Array.some(d => switch d { | EofLast => true | _ => false }) =>
    trimTrailingNewline(renderedContent)
  | _ => renderedContent
  }

  let skipGuard = switch allDirectives {
  | Some(ds) => {
      ds->Array.reduce(Ok(false), (acc, d) => {
        switch acc {
        | Error(_) => acc
        | Ok(true) => Ok(true)
        | Ok(false) =>
          switch d {
          | SkipIf(pattern) => shouldSkip(existingContent, pattern)
          | _ => Ok(false)
          }
        }
      })
    }
  | None => Ok(false)
  }

  switch skipGuard {
  | Error(e) => Error(e)
  | Ok(true) => Ok({content: existingContent, applied: false})
  | Ok(false) =>
  switch directive {
  | Inject(pattern) => {
      let result = injectRegex(existingContent, pattern, effectiveRendered)
      result->Result.map(content => {content, applied: true})
    }
  | After(pattern) => {
      let result = insertAfter(existingContent, pattern, effectiveRendered)
      result->Result.map(content => {content, applied: true})
    }
  | Before(pattern) => {
      let result = insertBefore(existingContent, pattern, effectiveRendered)
      result->Result.map(content => {content, applied: true})
    }
  | AtLine(line) => {
      let result = insertAtLine(existingContent, line, effectiveRendered)
      result->Result.map(content => {content, applied: true})
    }
  | Prepend => Ok({content: prependToContent(existingContent, effectiveRendered), applied: true})
  | Append => Ok({content: appendToContent(existingContent, effectiveRendered), applied: true})
  | SkipIf(_) => Ok({content: existingContent, applied: false})
  | EofLast => Ok({content: existingContent, applied: false})
  | _ => Ok({content: existingContent, applied: false}) // non-injection directives
  }
  }
}
