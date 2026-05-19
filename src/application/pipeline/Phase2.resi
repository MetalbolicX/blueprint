type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
}

type phase2Error = {
  message: string,
  partialCommit?: array<string>,
}

let executeShellCommands: (
  ~commands: array<Template.shellCommand>,
  ~cwd: string,
  ~shellConfig: option<Config.shellConfig>,
) => promise<result<int, string>>

let run: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~shellCommands: array<Template.shellCommand>,
  ~shellConfig: option<Config.shellConfig>,
) => promise<result<phase2Result, phase2Error>>

let rollback: string => promise<unit>
