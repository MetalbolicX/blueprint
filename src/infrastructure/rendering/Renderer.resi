type renderContext = {
  name: string,
  pascalName: string,
  names: string,
  pluralPascalName: string,
  cwd: string,
  actionfolder: string,
  attributes: dict<string>,
}

let render: (Template.template, renderContext) => result<string, string>
