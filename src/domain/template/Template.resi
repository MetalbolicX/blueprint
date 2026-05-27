type directive =
  | To(string)
  | From(string)
  | Inject(string)
  | After(string)
  | Before(string)
  | AtLine(int)
  | SkipIf(string)
  | Prepend
  | Append
  | EofLast
  | Force
  | UnlessExists
  | Tool(string)
  | Fetch(string)
  | Script(string)

type template = {
  sourcePath: string,
  directives: array<directive>,
  body: string,
}

type renderedFile = {
  sourcePath: string,
  targetPath: string,
  content: string,
  isInjection: bool,
}

type shellTarget =
  | InlineCommand(string)
  | ScriptFile(string)
  | Fetch(string)
  | ToolCall({
    name: string,
    toolDef: Config.shellTool,
    sourcePath: string,
  })

type shellCommand = {
  target: shellTarget,
  sourcePath: string,
}
