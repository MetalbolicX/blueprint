// Context — template rendering context with name variants and attributes
// Merge priority: CLI attrs > prompt answers > defaults > name variants
// Mirrors Go version's context.go

open FuncMap

type attrValue =
  | Scalar(string)
  | Values(array<string>)

type nameVariants = {
  name: string, // lowercase
  pascalName: string, // PascalCase
  names: string, // plural lowercase
  pluralPascalName: string, // plural PascalCase
}

type context = {
  cwd: string,
  actionfolder: string, // absolute path to manifest directory
  nameVariants: nameVariants,
  attributes: dict<attrValue>, // CLI --key value + prompt answers
}

// Generate name variants from base name
let makeNameVariants: string => nameVariants = baseName => {
  {
    name: baseName->snakeCase->String.toLowerCase,
    pascalName: baseName->pascalCase,
    names: baseName->snakeCase->String.toLowerCase->String.concat("s"),
    pluralPascalName: baseName->pascalCase->String.concat("s"),
  }
}

// Merge CLI attributes with prompt answers and defaults
// Priority: CLI > prompt answers > manifest defaults > name variants
let mergeAttributes: (
  ~cliAttributes: dict<attrValue>,
  ~promptAnswers: dict<attrValue>,
  ~manifestDefaults: dict<attrValue>,
  ~nameVariants: nameVariants,
) => dict<attrValue> = (~cliAttributes, ~promptAnswers, ~manifestDefaults, ~nameVariants) => {
  let merged = Dict.make()

  // Seed with manifest defaults
  manifestDefaults
  ->Dict.toArray
  ->Array.forEach(((k, v)) => {
    Dict.set(merged, k, v)
  })

  // Override with name variants (pre-seeded)
  Dict.set(merged, "name", Scalar(nameVariants.name))
  Dict.set(merged, "Name", Scalar(nameVariants.pascalName))
  Dict.set(merged, "names", Scalar(nameVariants.names))
  Dict.set(merged, "Names", Scalar(nameVariants.pluralPascalName))

  // Override with prompt answers
  promptAnswers
  ->Dict.toArray
  ->Array.forEach(((k, v)) => {
    Dict.set(merged, k, v)
  })

  // Override with CLI attributes (highest priority)
  cliAttributes
  ->Dict.toArray
  ->Array.forEach(((k, v)) => {
    Dict.set(merged, k, v)
  })

  merged
}

// Build full context from components
let build: (
  ~cwd: string,
  ~actionfolder: string,
  ~name: string,
  ~cliAttributes: dict<attrValue>=?,
  ~promptAnswers: dict<attrValue>=?,
  ~manifestDefaults: dict<attrValue>=?,
  unit,
) => context = (
  ~cwd,
  ~actionfolder,
  ~name,
  ~cliAttributes=?,
  ~promptAnswers=?,
  ~manifestDefaults=?,
  (),
) => {
  let nv = makeNameVariants(name)

  let defaults = switch manifestDefaults {
  | Some(d) => d
  | None => Dict.make()
  }

  let prompts = switch promptAnswers {
  | Some(p) => p
  | None => Dict.make()
  }

  let cli = switch cliAttributes {
  | Some(c) => c
  | None => Dict.make()
  }

  {
    cwd,
    actionfolder,
    nameVariants: nv,
    attributes: mergeAttributes(
      ~cliAttributes=cli,
      ~promptAnswers=prompts,
      ~manifestDefaults=defaults,
      ~nameVariants=nv,
    ),
  }
}

// Convert context to Renderer.renderContext for EJS rendering
let toRenderContext: context => Renderer.renderContext = ctx => {
  let plainAttrs = Dict.make()
  ctx.attributes->Dict.toArray->Array.forEach(((k, v)) => {
    switch v {
    | Scalar(s) => Dict.set(plainAttrs, k, s)
    | Values(arr) => Dict.set(plainAttrs, k, arr->Array.join(","))
    }
  })
  {
    name: ctx.nameVariants.name,
    pascalName: ctx.nameVariants.pascalName,
    names: ctx.nameVariants.names,
    pluralPascalName: ctx.nameVariants.pluralPascalName,
    cwd: ctx.cwd,
    actionfolder: ctx.actionfolder,
    attributes: plainAttrs,
  }
}
