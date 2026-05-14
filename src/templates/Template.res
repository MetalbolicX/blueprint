// Directive variants parsed from YAML frontmatter
type directive =
  | To(string)                    // target file path
  | Inject(string)                // regex pattern for injection
  | After(string)                 // insert after regex match
  | Before(string)                // insert before regex match
  | Prepend                       // prepend to file start
  | Append                        // append to file end
  | Force                         // overwrite without confirmation
  | Sh(string)                    // shell command after render

type template = {
  sourcePath: string,             // absolute path to .ejs.t file
  directives: array<directive>,   // parsed frontmatter directives
  body: string,                   // raw EJS template body
}

// Rendered file ready for staging or commit
type renderedFile = {
  sourcePath: string,             // source .ejs.t path
  targetPath: string,             // resolved target path (from `to` directive)
  content: string,                // rendered content
  isInjection: bool,              // true if inject/after/before/prepend/append
}

// Shell command to execute after Phase1
type shellCommand = {
  command: string,
  sourcePath: string,             // source template that declared the sh: directive
}