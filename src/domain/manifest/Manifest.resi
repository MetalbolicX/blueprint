type promptType = Input | Select | Confirm

type prompt = {
  name: string,
  promptType: promptType,
  description: string,
  default?: string,
  options?: array<string>,
}

type manifest = {
  name: string,
  classification: string,
  metadata?: dict<JSON.t>,
  prompts?: array<prompt>,
}

type validationError = {
  field: string,
  message: string,
}

let parsePromptType: string => option<promptType>
let promptTypeToString: promptType => string
let parse: string => result<manifest, string>
let validate: manifest => result<unit, array<validationError>>
