type parsedFrontmatter = {
  directives: array<Template.directive>,
  body: string,
}

let parse: string => result<parsedFrontmatter, string>


