type interface = {
  question: (string) => promise<string>,
  close: unit => unit,
}

type completer = (string, int) => promise<(array<string>, int)>

type readlineInterface = {
  question: (string, ~completer: completer=?) => promise<string>,
  close: unit => unit,
}

@module("readline")
external createInterface: (~input: node:stream$Readable, ~output: node:stream$Writable=?, unit) => readlineInterface = "createInterface"

@module("readline")
external moveCursor: (node:stream$Readable, int, int) => unit = "moveCursor"

@module("readline")
external clearLine: (node:stream$Readable, int) => unit = "clearLine"

@module("readline")
external cursorTo: (node:stream$Readable, int, ~y: int=?, unit) => unit = "cursorTo"