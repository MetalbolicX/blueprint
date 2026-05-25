open Bindings.NodeJs

let make: (
  ~createInterface: (
    ~input: Readline.streamReadable,
    ~output: Readline.streamWritable=?,
    unit,
  ) => Readline.readlineInterface=?,
  unit,
) => Ports.interactiveIO = (~createInterface=Readline.createInterface, ()) => {
  let rl = createInterface(~input=Readline.stdin, ~output=Readline.stdout, ())
  
  {
    ask: question => rl.question(question),
    askConfirm: async (~question, ~defaultYes=true) => {
      let suffix = defaultYes ? " [Y/n] " : " [y/N] "
      let answer = await rl.question(question ++ suffix)
      let normalized = String.trim(answer)->String.toLowerCase
      if normalized == "" {
        defaultYes
      } else {
        normalized == "y" || normalized == "yes"
      }
    },
    close: () => rl.close(),
  }
}
