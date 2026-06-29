/**
 * EnvFilter — environment variable filtering for shell execution
 * Ensures only explicitly allowed environment variables are passed to child processes
 */

type shellEnvEntry = {
  key: string,
  value: string, // literal or "$INHERITED_VAR"
}

type shellEnvConfig = {
  vars: array<shellEnvEntry>,
}

/**
 * Default safe env vars that are always included
 */
let defaultSafeVars = ["PATH", "HOME"]

/**
 * Checks if a value contains shell metacharacters that could be used for injection
 *
 * WS4: also rejects `${...}` shell parameter expansion. The existing `resolveValue`
 * only handles the bare `$VAR` form; the `${...}` form would otherwise fall
 * through to the child process shell and exfiltrate the named env value
 * regardless of `buildSafeEnv`'s filters.
 */
let containsShellMetachar: string => bool = value => {
  // Check for common shell injection characters
  String.includes(value, "&&") ||
    String.includes(value, "||") ||
    String.includes(value, ";") ||
    String.includes(value, "|") ||
    String.includes(value, "`") ||
    String.includes(value, "$(") ||
    String.includes(value, "${") ||
    String.includes(value, ">") ||
    String.includes(value, "<") ||
    String.includes(value, "\n")
}

/**
 * Resolves an env value that may contain $VAR reference
 */
let resolveValue: (string, dict<string>) => string = (value, inheritedEnv) => {
  if String.startsWith(value, "$") {
    let varName = String.slice(value, ~start=1)
    switch Dict.get(inheritedEnv, varName) {
    | Some(v) => v
    | None => ""
    }
  } else {
    value
  }
}

/**
 * Builds a safe environment dict for child process execution.
 *
 * @param shellEnv - Optional shell env config with explicit var overrides/additions
 * @param inheritedEnv - The parent process environment to filter
 * @returns A new dict containing only PATH, HOME, and explicitly configured vars
 */
let buildSafeEnv: (option<shellEnvConfig>, dict<string>) => dict<string> = (
  shellEnv,
  inheritedEnv,
) => {
  let result = Dict.make()

  // Always add default safe vars (PATH, HOME) if they exist in inherited env
  defaultSafeVars->Array.forEach(varName => {
    switch Dict.get(inheritedEnv, varName) {
    | Some(v) => Dict.set(result, varName, v)
    | None => ()
    }
  })

  // Add/override from shell.env config
  switch shellEnv {
  | Some(config) =>
    config.vars->Array.forEach(entry => {
      // Skip if value contains shell metacharacters (injection attempt)
      if !containsShellMetachar(entry.value) {
        let resolvedValue = resolveValue(entry.value, inheritedEnv)
        Dict.set(result, entry.key, resolvedValue)
      }
    })
  | None => ()
  }

  result
}