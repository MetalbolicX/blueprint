@val external prompt: (string, option<string>) => Nullable.t<string> = "prompt"
@val external confirm: string => bool = "confirm"

let make: unit => Ports.interactiveIO = () => {
  {
    ask: async question => {
      let result = prompt(question, None)
      switch Nullable.toOption(result) {
      | Some(ans) => ans
      | None => ""
      }
    },
    askConfirm: async (~question, ~defaultYes=true) => {
      let suffix = defaultYes ? " [Y/n] " : " [y/N] "
      let answer = prompt(question ++ suffix, None)
      switch Nullable.toOption(answer) {
      | Some(ans) => {
          let normalized = String.trim(ans)->String.toLowerCase
          if normalized == "" {
            defaultYes
          } else {
            normalized == "y" || normalized == "yes"
          }
        }
      | None => defaultYes
      }
    },
    close: () => {
      // Deno's prompt/confirm don't require an open/close lifecycle
      ()
    },
  }
}
