// EngineContext.res


let buildInitialContext: (
  ~fs: Ports.fileSystem,
  ~generatorPath: string,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
) => promise<Context.context> = async (~fs, ~generatorPath, ~name, ~cliAttributes) => {
  let cwd = switch await fs.fileExists(generatorPath) {
  | true => generatorPath
  | false => "."
  }

  Context.build(~cwd, ~actionfolder=generatorPath, ~name, ~cliAttributes, ())
}

let buildMergedContext: (
  ~initialContext: Context.context,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~promptAnswers: dict<string>,
  ~hookAttributes: dict<Context.attrValue>=?,
) => Context.context = (~initialContext, ~name, ~cliAttributes, ~promptAnswers, ~hookAttributes=?) => {
  let wrappedAnswers = Dict.make()
  promptAnswers->Dict.toArray->Array.forEach(((k, v)) => {
    Dict.set(wrappedAnswers, k, Context.Scalar(v))
  })

  Context.build(
    ~cwd=initialContext.cwd,
    ~actionfolder=initialContext.actionfolder,
    ~name,
    ~cliAttributes,
    ~promptAnswers=wrappedAnswers,
    ~hookAttributes?,
    (),
  )
}
