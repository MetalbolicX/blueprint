open Template

type renderedOutput = {
  sourcePath: string,
  targetPath: string,
  renderedBody: string,
}

let renderTargetPath: (~to: string, ~ejs: Ports.ejs, ~attributes: dict<string>) => result<string, string>
let resolveTargetPath: (~ejs: Ports.ejs, Template.directive, Context.context) => result<string, string>

let render: (
  ~template: template,
  ~context: Context.context,
  ~outputDir: string,
  ~conflictDecisions: option<array<ConflictResolver.conflictDecision>>,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~pathSecurity: Ports.pathSecurity,
  ~ejs: Ports.ejs,
  ~process: Ports.process,
) => promise<result<option<renderedOutput>, string>>
