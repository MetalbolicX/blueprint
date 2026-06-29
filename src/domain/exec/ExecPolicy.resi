/**
 * ExecPolicy — pure decision module for shell and binary execution.
 * See ExecPolicy.res for the behavioral contract.
 */

/**
 * The default bounded execution time, in milliseconds.
 */
let defaultTimeout: int

/**
 * Decision variants. The consumer is responsible for acting on each branch.
 *  - ExecFile: invoke via execFile with `args` (no shell interpretation).
 *  - ShellExact: invoke via exec with shell, only after an allowlist match.
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
) => decision
