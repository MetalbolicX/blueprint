type hookType = PreGenerate | PostGenerate

type hookResult = {
  hookType: hookType,
  output: string,
  exitCode: int,
}

let run: (~config: Config.config, ~cwd: string) => promise<result<unit, string>>
