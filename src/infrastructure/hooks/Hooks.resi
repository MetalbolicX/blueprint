type hookType = PreGenerate | PostGenerate

type hookResult = {
  hookType: hookType,
  output: string,
  exitCode: int,
}

let executeHook: (
  ~hook: Config.hookCommand,
  ~cwd: string,
  ~timeout: int,
  ~hookType: hookType,
  ~shellEnv: option<Config.shellEnv>,
) => promise<result<hookResult, string>>

let run: (
  ~config: Config.config,
  ~projectRoot: string,
  ~hookType: hookType,
  ~shellConfig: option<Config.shellConfig>,
) => promise<result<unit, string>>