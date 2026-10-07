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
 *  - Reject: do not invoke — surface `reason` to the caller.
 */
type decision =
  | ExecFile(string, array<string>)
  | Reject(string)

/**
 * Every execution requires an exact allowlist match; allowed commands use
 * ExecFile and rejected commands never reach a shell.
 */
let decide: (
  ~command: string,
  ~args: option<array<string>>,
  ~allowlist: array<string>,
) => decision
