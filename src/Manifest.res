// Manifest parsing and validation
// Declarative YAML manifest per generator, mirrors Go version's manifest.go

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
  metadata: option<Js.Dict.t<string>>,
  prompts: option<array<prompt>>,
}

type parseError = {
  message: string,
  line: option<int>,
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
      switch Js.Json.classify(obj) {
      | Js.Json.JObject(dict) =>
        switch Js.Dict.get(dict, key) {
        | Some(v) =>
          switch Js.Json.classify(v) {
          | Js.Json.JString(s) => Some(s)
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
    let getStringArray = (obj, key) => {
      switch Js.Json.classify(obj) {
      | Js.Json.JObject(dict) =>
        switch Js.Dict.get(dict, key) {
        | Some(v) =>
          switch Js.Json.classify(v) {
          | Js.Json.JArray(arr) =>
            arr->Js.Array.map(v' => {
              switch Js.Json.classify(v') {
              | Js.Json.JString(s) => Some(s)
              | _ => None
              }
            })->Js.Array.filterMap(x => x)->Some
          | _ => None
          }
        | None => None
        }
      | _ => None
      }
    }

    let getMetadata = (obj, key) => {
      switch Js.Json.classify(obj) {
      | Js.Json.JObject(dict) =>
        switch Js.Dict.get(dict, key) {
        | Some(v) =>
          switch Js.Json.classify(v) {
          | Js.Json.JObject(objDict) => Some(objDict)
          | _ => None
          }
        | None => None
        }
      | _ => None
      }
    }

    let getPrompts = (obj, key) => {
      switch Js.Json.classify(obj) {
      | Js.Json.JObject(dict) =>
        switch Js.Dict.get(dict, key) {
        | Some(v) =>
          switch Js.Json.classify(v) {
          | Js.Json.JArray(arr) =>
            arr->Js.Array.map(promptJson => {
              switch Js.Json.classify(promptJson) {
              | Js.Json.JObject(promptDict) => {
                  let name = getString(promptJson, "name")
                  let desc = getString(promptJson, "description")->Option.getWithDefault("")
                  let defaultVal = getOptString(promptJson, "default")
                  let opts = getStringArray(promptJson, "options")
                  let typeStr = getString(promptJson, "type")->Option.getWithDefault("input")
                  let pt = parsePromptType(typeStr)->Option.getWithDefault(Input)

                  switch name {
                  | Some(n) => Some({ name: n, promptType: pt, description: desc, default: defaultVal, options: opts })
                  | None => None
                  }
                }
              | _ => None
              }
            })->Js.Array.filterMap(x => x)->Some
          | _ => None
          }
        | None => None
        }
      | _ => None
      }
    }

    // Build manifest from JSON
    let name = getString(json, "name")->Option.getWithDefault("")
    let classification = getString(json, "classification")->Option.getWithDefault("")
    let metadata = getMetadata(json, "metadata")
    let prompts = getPrompts(json, "prompts")

    Ok({ name: name, classification: classification, metadata: metadata, prompts: prompts })
  } catch {
  | Js.Exn.Error(obj) =>
    let msg = switch Js.Exn.message(obj) {
    | Some(m) => m
    | None => "Failed to parse manifest"
    }
    Error(msg)
  }
}

// Validate manifest — returns error list if invalid
let validate: manifest => result<unit, array<validationError>> = manifest => {
  let errors = Js.Array.empty()

  if manifest.classification == "" {
    Js.Array.push({ field: "classification", message: "classification is required" }, errors)
  }

  switch manifest.prompts {
  | Some(prompts) =>
    prompts->Js.Array.forEach(p => {
      if p.name == "" {
        Js.Array.push({ field: "prompts.name", message: "prompt name cannot be empty" }, errors)
      }
      if p.promptType == Select && p.options == None {
        Js.Array.push({ field: "prompts.options", message: "select prompt requires options" }, errors)
      }
    })
  | None => ()
  }

  if Js.Array.length(errors) == 0 {
    Ok()
  } else {
    Error(errors)
  }
}