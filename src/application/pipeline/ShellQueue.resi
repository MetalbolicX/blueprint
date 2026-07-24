// ShellQueue.resi
open Template

let collectTemplate: (
  template,
  option<Config.shellConfig>,
  ~actionfolder: string,
  ~path: Ports.path,
  ~process: Ports.process,
) => result<array<shellCommand>, string>
