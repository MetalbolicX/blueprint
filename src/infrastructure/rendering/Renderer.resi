// WS4: cwd and actionfolder removed from the public renderContext type.
type renderContext = {
  name: string,
  pascalName: string,
  names: string,
  pluralPascalName: string,
  attributes: dict<string>,
}

let extractUndefinedVar: string => option<string>

let render: (Template.template, renderContext) => result<string, string>
