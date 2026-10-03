type parsedFrontmatter = {
  directives: array<Template.directive>,
  body: string,
}

let parse: (~path: Ports.path, string) => result<parsedFrontmatter, string>


