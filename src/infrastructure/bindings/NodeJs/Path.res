/**
 * Node.js path bindings — path manipulation
 */

@module("node:path")
external join: (string, string) => string = "join"

@module("node:path")
external resolve: (string, string) => string = "resolve"

@module("node:path")
external dirname: string => string = "dirname"

@module("node:path")
external basename: (string, ~ext: string=?) => string = "basename"

@module("node:path")
external isAbsolute: string => bool = "isAbsolute"
