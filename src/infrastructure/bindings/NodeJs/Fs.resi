/**
 * Node.js fs bindings interface
 */

type fileHandle

type readFileOptions = {encoding: string}
type writeFileOptions = {encoding: string}
type mkdirOptions = {recursive: bool}
type rmOptions = {recursive: bool}
type cpOptions = {recursive: bool}
type readdirOptions = {withFileTypes: bool}

type statResult = {
  isFile: unit => bool,
  isDirectory: unit => bool,
}

type accessOptions = {mode: int}

let readFile: (string, ~options: readFileOptions=?) => promise<string>
let writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit>
let mkdir: (string, ~options: mkdirOptions=?) => promise<string>
let rm: (string, ~options: rmOptions=?) => promise<unit>
let cp: (string, string, ~options: cpOptions=?) => promise<unit>
let readdir: (string, ~options: readdirOptions=?) => promise<array<string>>
let stat: string => promise<statResult>
let lstat: string => promise<statResult>
let access: (string, ~mode: int=?) => promise<unit>

let fOk: int
let fileExists: string => promise<bool>

// Internal sync mkdir — exposed for sibling modules in NodeJs/ directory
let mkdirSync: (string, ~options: mkdirOptions=?) => string
