type hooksConfig = {
  preGenerate?: string,
  postGenerate?: string,
  timeout?: int,
}

type config = {
  hooks?: hooksConfig,
  output?: string,
}

let parse: string => result<config, string>
let loadFrom: string => promise<result<option<config>, string>>
let defaultOutputDir: string
let defaultTimeout: int
