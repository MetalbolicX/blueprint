let resolve: (
  ~rl: Bindings.Readline.readlineInterface,
  ~prompts: array<Manifest.prompt>,
  ~force: bool,
) => promise<dict<string>>
