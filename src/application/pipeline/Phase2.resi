type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
  shellErrors?: array<string>,
}

type phase2Error = {
  message: string,
  partialCommit?: array<string>,
}

let executeShellCommands: (
  ~commands: array<Template.shellCommand>,
  ~cwd: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
) => promise<result<(int, array<string>), string>>

let run: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~shellCommands: array<Template.shellCommand>,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
) => promise<result<phase2Result, phase2Error>>

let rollback: (string, ~fs: Ports.fileSystem) => promise<unit>