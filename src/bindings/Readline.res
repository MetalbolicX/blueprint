type interface = {
  question: string => promise<string>,
  close: unit => unit,
}

type completer = (string, int) => promise<(array<string>, int)>

type readlineInterface = {
  question: (string, ~completer: completer=?) => promise<string>,
  close: unit => unit,
}

type streamReadable = unit
type streamWritable = unit

@module("readline")
external createInterface: (
  ~input: streamReadable,
  ~output: streamWritable=?,
  unit,
) => readlineInterface = "createInterface"

@module("readline")
external moveCursor: (streamReadable, int, int) => unit = "moveCursor"

@module("readline")
external clearLine: (streamReadable, int) => unit = "clearLine"

@module("readline")
external cursorTo: (streamReadable, int, ~y: int=?, unit) => unit = "cursorTo"
