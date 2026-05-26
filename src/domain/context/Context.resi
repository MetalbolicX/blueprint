type attrValue = Scalar(string) | Values(array<string>)

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
  attributes: dict<attrValue>,
}

let makeNameVariants: string => nameVariants

let mergeAttributes: (
  ~cliAttributes: dict<attrValue>,
  ~promptAnswers: dict<attrValue>,
  ~manifestDefaults: dict<attrValue>,
  ~nameVariants: nameVariants,
) => dict<attrValue>

let build: (
  ~cwd: string,
  ~actionfolder: string,
  ~name: string,
  ~cliAttributes: dict<attrValue>=?,
  ~promptAnswers: dict<attrValue>=?,
  ~manifestDefaults: dict<attrValue>=?,
  unit,
) => context

let toRenderContext: context => Renderer.renderContext
