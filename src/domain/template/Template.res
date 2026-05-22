// Directive variants parsed from YAML frontmatter
type directive =
  | To(string) // target file path
  | From(string) // external template file path
  | Inject(string) // regex pattern for injection
  | After(string) // insert after regex match
  | Before(string) // insert before regex match
  | AtLine(int) // inject at specific line number
  | SkipIf(string) // skip injection if regex matches existing content
  | Prepend // prepend to file start
  | Append // append to file end
  | EofLast // trim newline at end of injected payload
  | Force // overwrite without confirmation
  | UnlessExists // only render when target file does not exist
  | Sh(string) // legacy shell command (warn)
  | Tool(string) // tool name lookup
  | Fetch(string) // fetch URL content
  | Script(string) // script name for lookup + execution

type template = {
  sourcePath: string, // absolute path to .ejs.t file
  directives: array<directive>, // parsed frontmatter directives
  body: string, // raw EJS template body
}

// Rendered file ready for staging or commit
type renderedFile = {
  sourcePath: string, // source .ejs.t path
  targetPath: string, // resolved target path (from `to` directive)
  content: string, // rendered content
  isInjection: bool, // true if inject/after/before/prepend/append
}

// Shell command to execute after Phase1
type shellTarget =
  | InlineCommand(string)
  | ScriptFile(string)
  | Fetch(string) // fetch URL content (Phase2 downloads and writes)
  | ToolCall({
    name: string,
    toolDef: Config.shellTool,
    sourcePath: string,
  })

type shellCommand = {
  target: shellTarget,
  sourcePath: string, // source template that declared the directive
}
