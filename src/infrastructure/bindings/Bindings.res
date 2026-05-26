// Bindings - re-export all runtime bindings explicitly under namespaces
module NodeJs = NodeJs
module Ejs = Ejs
module Yaml = Yaml
module WebApis = WebApis

// We keep these for backwards compatibility for now so we don't break everything at once.
// Once everything consumes the ports, we can remove these top-level exports and force consumers
// to use `Bindings.NodeJs.Fs` or just use the `deps` ports.
module ChildProcess = NodeJs.ChildProcess
module Fs = NodeJs.Fs
module Os = NodeJs.Os
module ParseArgs = NodeJs.ParseArgs
module Path = NodeJs.Path
module Readline = NodeJs.Readline
module Util = NodeJs.Util
