/**
 * Typed bindings to Web APIs (browsers, Node.js 22+).
 */

module AbortSignal = {
  type t

  /**
   * Creates an AbortSignal that auto-aborts after `ms` milliseconds.
   * Available in browsers and Node.js 22+.
   */
  @val
  external timeout: int => t = "AbortSignal.timeout"
}