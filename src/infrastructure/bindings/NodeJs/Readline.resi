/**
 * Node.js readline bindings interface
 */

type interface = {
  question: string => promise<string>,
  close: unit => unit,
}

type completer = (string, int) => promise<(array<string>, int)>

type readlineInterface = {
  question: (string, ~completer: completer=?) => promise<string>,
  close: unit => unit,
}

type streamReadable
type streamWritable

let stdin: streamReadable
let stdout: streamWritable

let createInterface: (~input: streamReadable, ~output: streamWritable=?, unit) => readlineInterface
