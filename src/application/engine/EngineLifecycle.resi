// EngineLifecycle.resi

let cleanupOrphans: (~outputDir: string, ~fs: Ports.fileSystem, ~path: Ports.path, ~tmpRoot: string=?) => promise<unit>
let registerSignalHandlers: (~process: Ports.process, ~stagingDirRef: ref<option<string>>, ~fs: Ports.fileSystem) => unit
let cleanupPath: (~target: string, ~fs: Ports.fileSystem) => promise<unit>
