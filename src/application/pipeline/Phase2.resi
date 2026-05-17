type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
}

type phase2Error = {
  message: string,
  partialCommit: option<array<string>>,
}

let run: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~shellCommands: array<Template.shellCommand>,
) => promise<result<phase2Result, phase2Error>>
