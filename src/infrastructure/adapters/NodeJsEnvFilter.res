open Ports

let toEnvFilterConfig: shellEnvConfig => EnvFilter.shellEnvConfig = config => {
  vars: config.vars->Array.map(entry => ({key: entry.key, value: entry.value} :> EnvFilter.shellEnvEntry)),
}

let buildSafeEnv: (option<Ports.shellEnvConfig>, dict<string>) => dict<string> = (config, inheritedEnv) => {
  EnvFilter.buildSafeEnv(config->Option.map(toEnvFilterConfig), inheritedEnv)
}

let make: unit => envFilter = () => {
  buildSafeEnv,
}
