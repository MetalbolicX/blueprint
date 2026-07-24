/**
 * Node.js readline bindings — interactive line reading
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

@module("node:process") external stdin: streamReadable = "stdin"
@module("node:process") external stdout: streamWritable = "stdout"

@module("node:readline")
external createInterface: (
  ~input: streamReadable,
  ~output: streamWritable=?,
  unit,
) => readlineInterface = "createInterface"
