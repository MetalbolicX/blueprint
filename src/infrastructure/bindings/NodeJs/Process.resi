/**
 * Node.js process bindings interface
 */

let argv: array<string>
let env: dict<string>
let exit: int => unit
let cwd: unit => string
