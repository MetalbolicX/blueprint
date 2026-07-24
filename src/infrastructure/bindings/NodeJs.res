/**
 * Node.js bindings directory module — aggregates sub-modules from NodeJs/ directory
 *
 * ReScript directory module: NodeJs/ directory's sub-modules are accessible as
 * NodeJs.Fs, NodeJs.Path, etc. This aggregator file re-exports them for
 * Bindings.NodeJs.X access patterns.
 */

module Fs = Fs
module Path = Path
module Os = Os
module ChildProcess = ChildProcess
module Readline = Readline
module Util = Util
module ParseArgs = ParseArgs
module Process = Process
