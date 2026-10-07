// EngineLifecycle.resi

let cleanupOrphans: (~outputDir: string, ~fs: Ports.fileSystem, ~path: Ports.path, ~tmpRoot: string=?) => promise<unit>
let touchHeartbeat: (~fs: Ports.fileSystem, ~stagingDir: string, ~path: Ports.path) => promise<unit>
let registerSignalHandlers: (~process: Ports.process, ~stagingDirRef: ref<option<string>>, ~commitRollbackRef: ref<option<unit => promise<unit>>>, ~fs: Ports.fileSystem) => unit
let cleanupPath: (~target: string, ~fs: Ports.fileSystem) => promise<unit>
