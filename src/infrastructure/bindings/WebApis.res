/**
 * Typed bindings to Web APIs (browsers, Deno, Node.js 22+).
 */

module AbortSignal = {
  type t

  @val
  external timeout: int => t = "AbortSignal.timeout"
}