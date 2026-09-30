open Bindings.NodeJs

let make: (
  ~createInterface: (
    ~input: Readline.streamReadable,
    ~output: Readline.streamWritable=?,
    unit,
  ) => Readline.readlineInterface=? ,
  unit,
) => Ports.interactiveIO = (~createInterface=Readline.createInterface, ()) => {
  let rl = ref(None)
  let getInterface = () => switch rl.contents {
  | Some(interface) => interface
  | None => {
      let interface = createInterface(~input=Readline.stdin, ~output=Readline.stdout, ())
      rl := Some(interface)
      interface
    }
  }
  {
    ask: question => (getInterface()).question(question),
    askConfirm: async (~question, ~defaultYes=true) => {
      let suffix = defaultYes ? " [Y/n] " : " [y/N] "
      let answer = await (getInterface()).question(question ++ suffix)
      let normalized = String.trim(answer)->String.toLowerCase
      if normalized == "" {
        defaultYes
      } else {
        normalized == "y" || normalized == "yes"
      }
    },
    close: () => {
      switch rl.contents {
      | Some(interface) => {
          rl := None
          interface.close()
        }
      | None => ()
      }
    },
  }
}
