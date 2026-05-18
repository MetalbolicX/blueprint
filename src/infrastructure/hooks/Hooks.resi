type hookType = PreGenerate | PostGenerate

type hookResult = {
  hookType: hookType,
  output: string,
  exitCode: int,
}

let parseCommand: string => (string, string)
let executeHook: (
  ~command: string,
  ~cwd: string,
  ~timeout: int,
  ~hookType: hookType,
) => promise<result<hookResult, string>>
let run: (~config: Config.config, ~cwd: string, ~hookType: hookType) => promise<result<unit, string>>
