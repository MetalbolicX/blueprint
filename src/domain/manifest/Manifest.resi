type promptType = Input | Select | Confirm

type prompt = {
  name: string,
  promptType: promptType,
  description: string,
  default: option<string>,
  options: option<array<string>>,
}

type manifest = {
  name: string,
  classification: string,
  metadata: option<dict<JSON.t>>,
  prompts: option<array<prompt>>,
}

type validationError = {
  field: string,
  message: string,
}

let parsePromptType: string => option<promptType>
let promptTypeToString: promptType => string
let parse: string => result<manifest, string>
let validate: manifest => result<unit, array<validationError>>
