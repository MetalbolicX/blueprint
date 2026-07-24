// Staging.resi

let create: (~tmpDir: string, ~fs: Ports.fileSystem) => promise<result<string, string>>

let writeStagedFile: (
  ~stagingDir: string,
  ~targetPath: string,
  ~renderedBody: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, string>>

let removeStagingDir: (string, ~fs: Ports.fileSystem) => promise<unit>
