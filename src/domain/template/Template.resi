type directive =
  | To(string)
  | Inject(string)
  | After(string)
  | Before(string)
  | Prepend
  | Append
  | Force
  | Sh(string)

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

type shellCommand = {
  command: string,
  sourcePath: string,
}
