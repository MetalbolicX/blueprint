// Validation — pure input validation helpers (no I/O)
// Mirrors Go version's phase0/prompt_resolver.go validation

// Validate a raw answer against a numbered Select option list.
// Returns Ok(value) on a valid numeric selection, Ok(default) on empty
// input (so the caller can preserve default behavior without re-prompting),
// or Error(msg) on non-numeric / out-of-range input.
let _validateSelectInput: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
  ~default: string,
) => result<string, string> = (~answer, ~opts, ~default) => {
  let trimmed = String.trim(answer)
  if trimmed == "" {
    Ok(default)
  } else {
    switch Int.fromString(trimmed) {
    | None => Error("Please enter a number")
    | Some(n) =>
      switch opts[n - 1] {
      | Some(opt) => Ok(opt.value)
      | None => {
          let max = Int.toString(Array.length(opts))
          Error("Please enter a number between 1 and " ++ max)
        }
      }
    }
  }
}

// Split a comma-separated answer into (validValues, invalidTokens).
// Valid values are the option values whose numeric index is in range;
// invalid tokens are the original trimmed strings that did not resolve.
let _tokenizeMultiSelect: (
  ~answer: string,
  ~opts: array<Manifest.promptOption>,
) => (array<string>, array<string>) = (~answer, ~opts) => {
  let initial: (array<string>, array<string>) = ([], [])
  String.split(answer, ",")
  ->Array.map(s => String.trim(s))
  ->Array.filter(s => s != "")
  ->Array.reduce(initial, (acc, token) => {
    let (valid, invalid) = acc
    switch Int.fromString(token) {
    | Some(n) =>
      switch opts[n - 1] {
      | Some(opt) => (Array.concat(valid, [opt.value]), invalid)
      | None => (valid, Array.concat(invalid, [token]))
      }
    | None => (valid, Array.concat(invalid, [token]))
    }
  })
}

// Check if a value matches a compiled regex
let _matchesPattern: (string, RegExp.t) => bool = (value, re) => {
  RegExp.test(re, value)
}

// Compile a regex pattern string, returning error on invalid syntax
let _compilePattern: (
  ~pattern: string,
  ~promptName: string,
) => result<RegExp.t, Expression.resolveError> = (~pattern, ~promptName) => {
  try {
    Ok(RegExp.fromString(pattern))
  } catch {
  | JsExn(obj) =>
    let msg = JsExn.message(obj)->Option.getOr("Invalid regex pattern")
    Error(
      Expression.ValidationConfigError({
        prompt: promptName,
        message: "Invalid validate.pattern: " ++ msg,
      }),
    )
  }
}
