/**
 * ExecPolicy — pure decision module for shell and binary execution.
 * Decides between ExecFile(command, args) or Reject(reason).
 *
 * Every ToolCall route requires an exact tools allowlist match and executes
 * through execFile, so allowlist entries are never interpreted by a shell.
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
 *  - Reject: do not invoke — surface `reason` to the caller.
 */
type decision =
  | ExecFile(string, array<string>)
  | Reject(string)

/**
 * Pure decision: every route requires an allowlist match and executes with
 * structured args through execFile. No side effects, no IO.
 */
let decide: (
  ~command: string,
  ~args: option<array<string>>,
  ~allowlist: array<string>,
) => decision = (~command, ~args, ~allowlist) => {
  if !(allowlist->Array.some(entry => entry == command)) {
    Reject("Command not in tools allowlist: " ++ command)
  } else {
    ExecFile(command, args->Option.getOr([]))
  }
}
