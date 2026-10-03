open Ports

let buildEnvFilterConfig: ConfigTypes.shellEnv => shellEnvConfig = shellEnv => {
  let config = ShellBuilder.buildEnvFilterConfig(shellEnv)
  {vars: config.vars->Array.map(entry => {key: entry.key, value: entry.value})}
}

let make: unit => shellBuilder = () => {
  buildEnvFilterConfig,
}
