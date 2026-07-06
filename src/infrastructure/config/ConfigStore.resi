// ConfigStore — Interface
// Extracted from Config.res as part of T2 refactor

open ConfigTypes

let saveGlobalAtPath: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~configPath: string,
  globalConfig,
) => promise<result<unit, string>>

let saveGlobal: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~homeDir: string,
  globalConfig,
) => promise<result<unit, string>>

let loadGlobal: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~homeDir: string,
) => promise<result<option<globalConfig>, string>>

let loadFrom: (
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  string,
) => promise<result<option<config>, string>>