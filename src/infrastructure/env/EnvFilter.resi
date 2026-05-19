/**
 * EnvFilter — environment variable filtering for shell execution
 */

type shellEnvEntry = {
  key: string,
  value: string,
}

type shellEnvConfig = {
  vars: array<shellEnvEntry>,
}

let buildSafeEnv: (option<shellEnvConfig>, dict<string>) => dict<string>