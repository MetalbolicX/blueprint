type nameVariants = {
  name: string,
  pascalName: string,
  names: string,
  pluralPascalName: string,
}

type context = {
  cwd: string,
  actionfolder: string,
  nameVariants: nameVariants,
  attributes: dict<string>,
}

let makeNameVariants: string => nameVariants

let mergeAttributes: (
  ~cliAttributes: dict<string>,
  ~promptAnswers: dict<string>,
  ~manifestDefaults: dict<string>,
  ~nameVariants: nameVariants,
) => dict<string>

let build: (
  ~cwd: string,
  ~actionfolder: string,
  ~name: string,
  ~cliAttributes: dict<string>=?,
  ~promptAnswers: dict<string>=?,
  ~manifestDefaults: dict<string>=?,
  unit,
) => context

let toRenderContext: context => Renderer.renderContext
