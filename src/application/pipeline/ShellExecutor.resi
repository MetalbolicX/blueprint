// ShellExecutor.resi
open Template

let cleanupFetchTmpFiles: (array<string>, ~fs: Ports.fileSystem) => promise<unit>

let executeShellCommands: (
  ~commands: array<shellCommand>,
  ~cwd: string,
  ~stagingDir: string,
  ~shellConfig: option<Config.shellConfig>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~process: Ports.process,
  ~shell: Ports.shell,
  ~fetcher: Ports.fetcher,
  ~pathSecurity: Ports.pathSecurity,
  ~shellBuilder: Ports.shellBuilder,
  ~envFilter: Ports.envFilter,
) => promise<result<int, string>>
