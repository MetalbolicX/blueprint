type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
}

let executeShellCommands: (
  ~commands: array<Template.shellCommand>,
  ~cwd: string,
  ~stagingDir: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
) => promise<result<int, string>>

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
) => promise<result<phase2Result, Commit.phase2Error>>
