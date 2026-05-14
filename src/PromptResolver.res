// PromptResolver — interactive prompt resolution via node:readline
// Supports input, select, and confirm prompt types
// Mirrors Go version's phase0/prompt_resolver.go

open Bindings

type promptAnswer = {
  name: string,
  value: string,
}

// Ask a single question based on prompt type
let askPrompt: (
  ~rl: Readline.readlineInterface,
  ~prompt: Manifest.prompt,
) => promise<string> = (~rl, ~prompt) => {
  let questionText = prompt.description ++
    (
      switch prompt.default {
      | Some(d) => " [" ++ d ++ "]"
      | None => ""
      }
    ) ++ ": "

  switch prompt.promptType {
  | Manifest.Input =>
    rl.question(questionText)

  | Manifest.Select =>
    // Show numbered options
    switch prompt.options {
    | Some(opts) if Js.Array.length(opts) > 0 => {
        let optionsText = opts->Js.Array.mapi((opt, i) => {
          "  " ++ (i + 1)->Js.Int.toString ++ ". " ++ opt
        })->Js.Array.join("\n")

        let fullQuestion = optionsText ++ "\n" ++ questionText

        rl.question(fullQuestion)->Promise.then(answer => {
          let idx = Js.Int.fromString(Js.String.trim(answer))->Option.getWithDefault(1) - 1
          let selected = opts[idx]->Option.getWithDefault(opts[0]->Option.getExn)
          Promise.resolve(selected)
        })
      }
    | _ => rl.question(questionText)
    }

  | Manifest.Confirm =>
    rl.question(questionText ++ " (y/n) ")->Promise.then(answer => {
      let trimmed = Js.String.trim(answer)->Js.String.toLowerCase
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
) => promise<Js.Dict.t<string>> = (~rl, ~prompts, ~force) => {
  let answers = Js.Dict.empty()

  if force {
    // In force mode, use defaults only
    prompts->Js.Array.forEach(p => {
      switch p.default {
      | Some(d) => Js.Dict.set(answers, p.name, d)
      | None => Js.Dict.set(answers, p.name, "")
      }
    })
  } else {
    // Interactive mode — ask each prompt
    let rec loop = (idx, prompts) => {
      if idx >= Js.Array.length(prompts) {
        Promise.resolve()
      } else {
        let prompt = prompts[idx]
        askPrompt(~rl, ~prompt)->Promise.then(answer => {
          let finalAnswer = if Js.String.trim(answer) == "" {
            prompt.default->Option.getWithDefault("")
          } else {
            answer
          }
          Js.Dict.set(answers, prompt.name, finalAnswer)
          loop(idx + 1, prompts)
        })
      }
    }

    loop(0, prompts)->Promise.then(_ => Promise.resolve(answers))
  }
}

// Readline interface lifecycle
let createReadline: unit => Readline.readlineInterface = () => {
  Readline.createInterface(
    ~input=Node.Process.stdin,
    ~output=Node.Process.stdout,
    (),
  )
}

let closeReadline: Readline.readlineInterface => unit = rl => {
  rl.close()
}