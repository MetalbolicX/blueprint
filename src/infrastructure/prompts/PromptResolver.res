// PromptResolver — interactive prompt resolution via node:readline
// Supports input, select, and confirm prompt types
// Mirrors Go version's phase0/prompt_resolver.go

open Bindings

type promptAnswer = {
  name: string,
  value: string,
}

// Ask a single question based on prompt type
let askPrompt: (~rl: Readline.readlineInterface, ~prompt: Manifest.prompt) => promise<string> = (
  ~rl,
  ~prompt,
) => {
  let questionText =
    prompt.description ++
    switch prompt.default {
    | Some(d) => " [" ++ d ++ "]"
    | None => ""
    } ++ ": "

  switch prompt.promptType {
  | Manifest.Input => rl.question(questionText)

  | Manifest.Select =>
    // Show numbered options
    switch prompt.options {
    | Some(opts) if Array.length(opts) > 0 => {
        let optionsText =
          opts
          ->Array.mapWithIndex((opt, i) => {
            "  " ++ Int.toString(i + 1) ++ ". " ++ opt
          })
          ->Array.join("\n")

        let fullQuestion = optionsText ++ "\n" ++ questionText

        rl.question(fullQuestion)->Promise.then(answer => {
          let trimmedAnswer = String.trim(answer)
          let idx = switch Int.fromString(trimmedAnswer) {
          | Some(n) => n - 1
          | None => 0
          }
          let selected = switch opts[idx] {
          | Some(s) => s
          | None => ""
          }
          Promise.resolve(selected)
        })
      }
    | _ => rl.question(questionText)
    }

  | Manifest.Confirm =>
    rl.question(questionText ++ " (y/n) ")->Promise.then(answer => {
      let trimmed = String.trim(answer)->String.toLowerCase
      if trimmed == "y" || trimmed == "yes" || trimmed == "" {
        Promise.resolve("true")
      } else {
        Promise.resolve("false")
      }
    })
  }
}

// Resolve all prompts in a manifest, returning answers as dict
let resolve: (
  ~rl: Readline.readlineInterface,
  ~prompts: array<Manifest.prompt>,
  ~force: bool,
) => promise<dict<string>> = (~rl, ~prompts, ~force) => {
  let answers = Dict.make()

  if force {
    // In force mode, use defaults only
    prompts->Array.forEach(p => {
      switch p.default {
      | Some(d) => Dict.set(answers, p.name, d)
      | None => Dict.set(answers, p.name, "")
      }
    })
    Promise.resolve(answers)
  } else {
    // Interactive mode — ask each prompt
    let rec loop = (idx, prompts) => {
      if idx >= Array.length(prompts) {
        Promise.resolve(answers)
      } else {
        switch prompts[idx] {
        | Some(prompt) =>
          askPrompt(~rl, ~prompt)->Promise.then(answer => {
            let finalAnswer = if String.trim(answer) == "" {
              prompt.default->Option.getOr("")
            } else {
              answer
            }
            answers->Dict.set(prompt.name, finalAnswer)
            loop(idx + 1, prompts)
          })
        | None =>
          Promise.resolve(answers)
        }
      }
    }

    loop(0, prompts)->Promise.then(_ => Promise.resolve(answers))
  }
}

// Readline interface lifecycle
let createReadline: unit => Readline.readlineInterface = () => {
  Readline.createInterface(~input=(), ~output=(), ())
}

let closeReadline: Readline.readlineInterface => unit = rl => {
  rl.close()
}
