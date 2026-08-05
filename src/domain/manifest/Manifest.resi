type promptType = Input | Select | Confirm | MultiSelect

type promptValidation = {pattern: string, message: string}

type promptOption = {label: string, value: string}

type prompt = {
  name: string,
  promptType: promptType,
  description: string,
  default?: string,
  @as("when") when_?: string,
  options?: array<promptOption>,
  validate?: promptValidation,
}

type generatorHooks = {
  preGenerate?: string,
  postGenerate?: string,
}

type manifest = {
  name: string,
  classification: string,
  description?: string,
  metadata?: dict<JSON.t>,
  prompts?: array<prompt>,
  hooks?: generatorHooks,
}

type validationError = {
  field: string,
  message: string,
}

let parsePromptType: string => option<promptType>
let parsePromptTypeFromInput: string => promptType
let promptTypeToString: promptType => string
let promptRequiresOptions: promptType => bool
let parse: (~yamlParser: Ports.yamlParser, ~yaml: string) => result<manifest, string>
let validate: manifest => result<unit, array<validationError>>
let validationErrorsToString: array<validationError> => string
