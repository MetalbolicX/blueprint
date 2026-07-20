// Manifest parsing and validation
// Declarative YAML manifest per generator, mirrors Go version's manifest.go

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

// Parse YAML string into manifest record
let parsePromptType: string => option<promptType> = s => {
  switch s {
  | "input" => Some(Input)
  | "select" => Some(Select)
  | "confirm" => Some(Confirm)
  | "multi-select" => Some(MultiSelect)
  | _ => None
  }
}

let promptTypeToString: promptType => string = pt => {
  switch pt {
  | Input => "input"
  | Select => "select"
  | Confirm => "confirm"
  | MultiSelect => "multi-select"
  }
}

let promptOptionToJson: promptOption => JSON.t = option => {
  let dict = Dict.make()
  Dict.set(dict, "label", JSON.String(option.label))
  Dict.set(dict, "value", JSON.String(option.value))
  JSON.Object(dict)
}

let promptValidationToJson: promptValidation => JSON.t = validation => {
  let dict = Dict.make()
  Dict.set(dict, "pattern", JSON.String(validation.pattern))
  Dict.set(dict, "message", JSON.String(validation.message))
  JSON.Object(dict)
}

let promptToJsonObject: prompt => dict<JSON.t> = prompt => {
  let dict = Dict.make()
  Dict.set(dict, "name", JSON.String(prompt.name))
  Dict.set(dict, "type", JSON.String(promptTypeToString(prompt.promptType)))
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

let appendPromptPreservingComments: (~yamlContent: string, ~prompt: prompt) => result<string, string> = (
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

let parse: string => result<manifest, string> = yamlContent => {
  try {
    let json = Bindings.Yaml.parse(yamlContent)

    // Helper to get string field
    let getString = (obj, key) => {
      switch obj {
      | JSON.Object(dict) =>
        switch dict->Dict.get(key) {
        | Some(v) =>
          switch v {
          | JSON.String(s) => Some(s)
          | _ => None
          }
        | None => None
        }
      | _ => None
      }
    }

    // Helper to get optional string
    let getOptString = (obj, key) => {
      switch getString(obj, key) {
      | Some(s) => Some(s)
      | None => None
      }
    }

    let getMetadata = (obj, key) => {
      switch obj {
      | JSON.Object(dict) =>
        switch dict->Dict.get(key) {
        | Some(v) =>
          switch v {
          | JSON.Object(objDict) => Some(objDict)
          | _ => None
          }
        | None => None
        }
      | _ => None
      }
    }

    let getPrompts = (obj, key) => {
      switch obj {
      | JSON.Object(dict) =>
        switch dict->Dict.get(key) {
        | Some(v) =>
          switch v {
          | JSON.Array(arr) =>
            arr
            ->Array.map(promptJson => {
              switch promptJson {
              | JSON.Object(_promptDict) => {
                  let name = getString(promptJson, "name")
                  let desc = getString(promptJson, "description")->Option.getOr("")
                  let defaultVal = getOptString(promptJson, "default")
                  let whenVal = getOptString(promptJson, "when")
                  let typeStr = getString(promptJson, "type")->Option.getOr("input")
                  let pt = parsePromptType(typeStr)->Option.getOr(Input)

                  // Parse options: support both string arrays and {label, value} objects
                  let opts = switch promptJson {
                  | JSON.Object(pd) =>
                    switch pd->Dict.get("options") {
                    | Some(JSON.Array(optArr)) =>
                      let parsed =
                        optArr->Array.map(optJson => {
                          switch optJson {
                          | JSON.String(s) => Some({label: s, value: s})
                          | JSON.Object(_optDict) => {
                              let lbl = getString(optJson, "label")
                              let val = getString(optJson, "value")
                              switch (lbl, val) {
                              | (Some(l), Some(v)) => Some({label: l, value: v})
                              | _ => None
                              }
                            }
                          | _ => None
                          }
                        })
                      let filtered = parsed->Array.filterMap(x => x)
                      if Array.length(filtered) == Array.length(optArr) {
                        Some(filtered)
                      } else {
                        None
                      }
                    | _ => None
                    }
                  | _ => None
                  }

                  // Parse validate: {pattern, message}
                  let validate = switch promptJson {
                  | JSON.Object(pd) =>
                    switch pd->Dict.get("validate") {
                    | Some(JSON.Object(vDict)) =>
                      let pattern = Dict.get(vDict, "pattern")
                      let message = Dict.get(vDict, "message")
                      switch (pattern, message) {
                      | (Some(JSON.String(p)), Some(JSON.String(m))) =>
                        if p != "" {
                          Some({pattern: p, message: m})
                        } else {
                          None
                        }
                      | _ => None
                      }
                    | _ => None
                    }
                  | _ => None
                  }

                  switch name {
                  | Some(n) =>
                    Some({
                      name: n,
                      promptType: pt,
                      description: desc,
                      default: ?defaultVal,
                      when_: ?whenVal,
                      options: ?opts,
                      validate: ?validate,
                    })
                  | None => None
                  }
                }
              | _ => None
              }
            })
            ->Array.filterMap(x => x)
            ->Some
          | _ => None
          }
        | None => None
        }
      | _ => None
      }
    }

    // Build manifest from JSON
    let name = getString(json, "name")->Option.getOr("")
    let classification = getString(json, "classification")->Option.getOr("")
    let metadata = getMetadata(json, "metadata")
    let prompts = getPrompts(json, "prompts")

    Ok({name, classification, metadata: ?metadata, prompts: ?prompts})
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "Failed to parse manifest"
    }
    Error(msg)
  }
}

// Validate manifest — returns error list if invalid
let validate: manifest => result<unit, array<validationError>> = manifest => {
  let errors: array<validationError> = []

  if manifest.classification == "" {
    Js.Array.push({field: "classification", message: "classification is required"}, errors)->ignore
  }

  switch manifest.prompts {
  | Some(prompts) =>
    prompts->Array.forEach(p => {
      if p.name == "" {
        Js.Array.push(
          {field: "prompts.name", message: "prompt name cannot be empty"},
          errors,
        )->ignore
      }
      if (p.promptType == Select || p.promptType == MultiSelect) && p.options == None {
        Js.Array.push(
          {field: "prompts.options", message: "select prompt requires options"},
          errors,
        )->ignore
      }
      switch p.validate {
      | Some(v) if v.pattern == "" =>
        Js.Array.push(
          {field: "prompts.validate.pattern", message: "validate.pattern cannot be empty"},
          errors,
        )->ignore
      | _ => ()
      }
    })
  | None => ()
  }

  if Array.length(errors) == 0 {
    Ok()
  } else {
    Error(errors)
  }
}

// Format an array of validation errors as `field: message; field: message`.
// Used by callers that surface multiple manifest errors together.
let validationErrorsToString: array<validationError> => string = errors => {
  errors
  ->Array.map(e => e.field ++ ": " ++ e.message)
  ->Array.join("; ")
}
