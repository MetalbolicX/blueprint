// Context — template rendering context with name variants and attributes
// Merge priority: CLI attrs > prompt answers > defaults > name variants
// Mirrors Go version's context.go

open Templates.FuncMap

type nameVariants = {
  name: string,          // lowercase
  Name: string,          // PascalCase
  names: string,         // plural lowercase
  Names: string,         // plural PascalCase
}

type context = {
  cwd: string,
  actionfolder: string,   // absolute path to manifest directory
  nameVariants: nameVariants,
  attributes: Js.Dict.t<string>,  // CLI --key value + prompt answers
}

// Generate name variants from base name
let makeNameVariants: string => nameVariants = baseName => {
  {
    name: baseName->snakeCase->Js.String.toLowerCase,
    Name: baseName->pascalCase,
    names: baseName->snakeCase->Js.String.toLowerCase->Js.String.concat("s"),
    Names: baseName->pascalCase->Js.String.concat("s"),
  }
}

// Merge CLI attributes with prompt answers and defaults
// Priority: CLI > prompt answers > manifest defaults > name variants
let mergeAttributes: (
  ~cliAttributes: Js.Dict.t<string>,
  ~promptAnswers: Js.Dict.t<string>,
  ~manifestDefaults: Js.Dict.t<string>,
  ~nameVariants: nameVariants,
) => Js.Dict.t<string> = (
  ~cliAttributes,
  ~promptAnswers,
  ~manifestDefaults,
  ~nameVariants,
) => {
  let merged = Js.Dict.empty()

  // Seed with manifest defaults
  manifestDefaults->Js.Dict.entries->Js.Array.forEach(((k, v)) => {
    Js.Dict.set(merged, k, v)
  })

  // Override with name variants (pre-seeded)
  Js.Dict.set(merged, "name", nameVariants.name)
  Js.Dict.set(merged, "Name", nameVariants.Name)
  Js.Dict.set(merged, "names", nameVariants.names)
  Js.Dict.set(merged, "Names", nameVariants.Names)

  // Override with prompt answers
  promptAnswers->Js.Dict.entries->Js.Array.forEach(((k, v)) => {
    Js.Dict.set(merged, k, v)
  })

  // Override with CLI attributes (highest priority)
  cliAttributes->Js.Dict.entries->Js.Array.forEach(((k, v)) => {
    Js.Dict.set(merged, k, v)
  })

  merged
}

// Build full context from components
let build: (
  ~cwd: string,
  ~actionfolder: string,
  ~name: string,
  ~cliAttributes: Js.Dict.t<string>=?,
  ~promptAnswers: Js.Dict.t<string>=?,
  ~manifestDefaults: Js.Dict.t<string>=?,
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
  | None => Js.Dict.empty()
  }

  let prompts = switch promptAnswers {
  | Some(p) => p
  | None => Js.Dict.empty()
  }

  let cli = switch cliAttributes {
  | Some(c) => c
  | None => Js.Dict.empty()
  }

  {
    cwd: cwd,
    actionfolder: actionfolder,
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
let toRenderContext: context => Templates.Renderer.renderContext = ctx => {
  {
    name: ctx.nameVariants.name,
    Name: ctx.nameVariants.Name,
    names: ctx.nameVariants.names,
    Names: ctx.nameVariants.Names,
    cwd: ctx.cwd,
    actionfolder: ctx.actionfolder,
    attributes: ctx.attributes,
  }
}