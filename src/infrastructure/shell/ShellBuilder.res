// ShellBuilder: constructs shell-related configurations, like EnvFilter.shellEnvConfig

let buildEnvFilterConfig: Config.shellEnv => EnvFilter.shellEnvConfig = shellEnv => {
  let entries: array<EnvFilter.shellEnvEntry> =
    shellEnv.vars->Dict.toArray->Array.map(((key, value)) => {
      let entry: EnvFilter.shellEnvEntry = {key: key, value: value}
      entry
    })
  {vars: entries}
}
