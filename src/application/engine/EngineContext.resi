// EngineContext.resi


let buildInitialContext: (
  ~fs: Ports.fileSystem,
  ~generatorPath: string,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
) => promise<Context.context>

let buildMergedContext: (
  ~initialContext: Context.context,
  ~name: string,
  ~cliAttributes: dict<Context.attrValue>,
  ~promptAnswers: dict<string>,
) => Context.context
