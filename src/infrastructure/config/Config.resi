type hooksConfig = {
  preGenerate: option<string>,
  postGenerate: option<string>,
  timeout: option<int>,
}

type config = {
  hooks: option<hooksConfig>,
  output: option<string>,
}

let parse: string => result<config, string>
let loadFrom: string => promise<result<option<config>, string>>
let defaultOutputDir: string
let defaultTimeout: int
