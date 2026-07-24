/**
 * Node.js path bindings interface
 */

let join: (string, string) => string
let resolve: (string, string) => string
let dirname: string => string
let basename: (string, ~ext: string=?) => string
let isAbsolute: string => bool
