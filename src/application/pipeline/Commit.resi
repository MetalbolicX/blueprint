type backupEntry = {
  outputPath: string,
  backupPath: string,
}

type rollbackFailure = {
  path: string,
  reason: string,
}

type phase2Error = {
  message: string,
  partialCommit?: array<string>,
  catastrophic?: bool,
  failedRollbackFiles?: array<string>,
}

let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
) => promise<result<(int, array<backupEntry>), phase2Error>>

let rollbackOutput: (
  ~committedFiles: array<string>,
  ~backups: array<backupEntry>,
  ~outputDir: string,
  ~path: Ports.path,
  ~fs: Ports.fileSystem,
) => promise<result<unit, array<rollbackFailure>>>

let rollback: (string, ~tmpRoot: string, ~path: Ports.path, ~fs: Ports.fileSystem) => promise<result<unit, string>>
