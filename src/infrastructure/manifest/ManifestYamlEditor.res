// ManifestYamlEditor — YAML DOM mutation for manifest files
// Moved from src/domain/manifest/Manifest.res to keep domain layer free of YAML library FFI

let promptOptionToJson: Manifest.promptOption => JSON.t = option => {
  let dict = Dict.make()
  Dict.set(dict, "label", JSON.String(option.label))
  Dict.set(dict, "value", JSON.String(option.value))
  JSON.Object(dict)
}

let promptValidationToJson: Manifest.promptValidation => JSON.t = validation => {
  let dict = Dict.make()
  Dict.set(dict, "pattern", JSON.String(validation.pattern))
  Dict.set(dict, "message", JSON.String(validation.message))
  JSON.Object(dict)
}

let promptToJsonObject: Manifest.prompt => dict<JSON.t> = prompt => {
  let dict = Dict.make()
  Dict.set(dict, "name", JSON.String(prompt.name))
  Dict.set(dict, "type", JSON.String(Manifest.promptTypeToString(prompt.promptType)))
  Dict.set(dict, "description", JSON.String(prompt.description))

  switch prompt.default {
  | Some(value) => Dict.set(dict, "default", JSON.String(value))
  | None => ()
  }

  switch prompt.when_ {
  | Some(value) => Dict.set(dict, "when", JSON.String(value))
  | None => ()
  }

  switch prompt.options {
  | Some(options) => Dict.set(dict, "options", JSON.Array(options->Array.map(promptOptionToJson)))
  | None => ()
  }

  switch prompt.validate {
  | Some(validate) => Dict.set(dict, "validate", promptValidationToJson(validate))
  | None => ()
  }

  dict
}

let appendPromptPreservingComments: (~yamlContent: string, ~prompt: Manifest.prompt) => result<string, string> = (
  ~yamlContent,
  ~prompt,
) => {
  try {
    let doc = Bindings.Yaml.parseDocument(yamlContent)

    if Bindings.Yaml.hasErrors(doc) {
      Error("Failed to parse manifest")
    } else {
      let promptValue = JSON.Object(promptToJsonObject(prompt))

      let promptCount =
        switch Bindings.Yaml.parse(yamlContent) {
        | JSON.Object(dict) =>
          switch Dict.get(dict, "prompts") {
          | Some(JSON.Array(prompts)) => Some(Array.length(prompts))
          | _ => None
          }
        | _ => None
        }

      switch promptCount {
      | Some(count) => {
          let appendPath: array<JSON.t> = [JSON.String("prompts"), JSON.Number(Float.fromInt(count))]
          Bindings.Yaml.addInAtPath(doc, appendPath, promptValue)
        }
      | None => Bindings.Yaml.addIn(doc, ["prompts"], [promptValue])
      }

      Ok(Bindings.Yaml.documentToString(doc))
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to append prompt to manifest"
    }
    Error(msg)
  }
}
