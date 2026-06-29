/**
 * ExecPolicy — pure decision module for shell and binary execution.
 * Decides between ExecFile(command, args), ShellExact(command), or Reject(reason).
 *
 * Used by ShellExecutor (tool calls, scripts) and Hooks (path-based hooks) so the
 * same hybrid policy is enforced at every execution boundary.
 */

/**
 * The default bounded execution time, in milliseconds. Mirrors the spec's
 * "must stop every tool/script run that exceeds 30 seconds" requirement.
 */
let defaultTimeout: int = 30000

/**
 * Decision variants. The consumer is responsible for acting on each branch:
 *  - ExecFile: invoke via child_process.execFile (no shell interpretation),
 *    passing `args` as a structured array.
 *  - ShellExact: invoke via child_process.exec with `shell: true`. Use only when
 *    `command` is an exact match against an allowlist entry.
 *  - Reject: do not invoke — surface `reason` to the caller.
 */
type decision =
  | ExecFile(string, array<string>)
  | ShellExact(string)
  | Reject(string)

/**
 * Pure decision: structured args → ExecFile; no args + allowlist match →
 * ShellExact; no args + no match → Reject. No side effects, no IO.
 */
let decide: (
  ~command: string,
  ~args: option<array<string>>,
  ~allowlist: array<string>,
) => decision = (~command, ~args, ~allowlist) => {
  switch args {
  | Some(structuredArgs) => ExecFile(command, structuredArgs)
  | None =>
    if allowlist->Array.some(entry => entry == command) {
      ShellExact(command)
    } else {
      Reject("Command not in tools allowlist: " ++ command)
    }
  }
}
