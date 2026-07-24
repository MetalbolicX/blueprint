/**
 * Node.js process bindings — process lifecycle
 */

@module("node:process") external argv: array<string> = "argv"
@module("node:process") external env: dict<string> = "env"
@module("node:process") external exit: int => unit = "exit"
@module("node:process") external cwd: unit => string = "cwd"
