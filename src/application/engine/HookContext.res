// HookContext.res — pure stdout→attributes parser (no IO, no side effects)
// Uses Ports.yamlParser (infrastructure adapter for YAML/JSON parsing).
// This is the fail-closed bridge: pre_generate hook stdout is parsed only when safe.

open Context

let maxStdoutBytes = 65536 // 64 KiB cap

let reservedKeys = ["name", "Name", "names", "Names", "h"]

// parse: (~stdout: string, ~yamlParser: Ports.yamlParser) => result<dict<attrValue>, string>
// Empty/whitespace → Ok(emptyDict). Malformed JSON / non-object / non-string value /
// reserved key / oversized → Error(string).
let parse: (~stdout: string, ~yamlParser: Ports.yamlParser) => result<dict<attrValue>, string> = (~stdout, ~yamlParser) => {
  let trimmed = String.trim(stdout)
  if trimmed == "" {
    Ok(Dict.make())
  } else if String.length(trimmed) > maxStdoutBytes {
    Error("pre_generate hook stdout exceeds " ++ Int.toString(maxStdoutBytes) ++ " bytes")
  } else {
    let json = switch yamlParser.parse(trimmed) {
    | Ok(v) => Ok(v)
    | Error(e) => Error("pre_generate hook stdout is not valid JSON: " ++ e)
    }
    switch json {
    | Error(e) => Error(e)
    | Ok(json) =>
      switch json {
      | JSON.Object(entries) =>
        let result = Dict.make()
        let acc = ref(Ok(()))
        entries->Dict.toArray->Array.forEach(((k, v)) => {
          switch acc.contents {
          | Error(_) => () // short-circuit on first error
          | Ok(_) =>
            if reservedKeys->Array.some(r => r == k) {
              acc := Error("pre_generate hook output uses reserved key: " ++ k)
            } else {
              switch v {
              | JSON.String(s) => Dict.set(result, k, Scalar(s))
              | _ => acc := Error("pre_generate hook value for '" ++ k ++ "' must be a string")
              }
            }
          }
        })
        switch acc.contents {
        | Error(e) => Error(e)
        | Ok(_) => Ok(result)
        }
      | _ => Error("pre_generate hook stdout must be a JSON object")
      }
    }
  }
}
