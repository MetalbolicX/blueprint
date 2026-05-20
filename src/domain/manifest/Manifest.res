// Manifest parsing and validation
// Declarative YAML manifest per generator, mirrors Go version's manifest.go

type promptType = Input | Select | Confirm

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

@@warning("-34")
type parseError = {
  message: string,
  line?: int,
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
  | _ => None
  }
}

let promptTypeToString: promptType => string = pt => {
  switch pt {
  | Input => "input"
  | Select => "select"
  | Confirm => "confirm"
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

    // Helper to get array of strings
    let _getStringArray = (obj, key) => {
      switch obj {
      | JSON.Object(dict) =>
        switch dict->Dict.get(key) {
        | Some(v) =>
          switch v {
          | JSON.Array(arr) =>
            arr
            ->Array.map(v' => {
              switch v' {
              | JSON.String(s) => Some(s)
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
      if p.promptType == Select && p.options == None {
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
