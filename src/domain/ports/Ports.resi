type readFileOptions = {encoding: string}
type writeFileOptions = {encoding: string}
type mkdirOptions = {recursive: bool}
type rmOptions = {recursive: bool}
type cpOptions = {recursive: bool}
type readdirOptions = {withFileTypes: bool}
type statResult = {isDirectory: unit => bool, isFile: unit => bool, mtimeMs?: float}
type lstatResult = {isDirectory: unit => bool, isFile: unit => bool, isSymbolicLink: unit => bool}

type hookType = PreGenerate | PostGenerate
type hookResult = {hookType: hookType, output: string, exitCode: int}
type yamlParser = {parse: string => result<JSON.t, string>}
type ejs = {
  renderString: (~template: string, ~context: dict<string>) => result<string, string>,
  renderFile: (~path: string, ~context: dict<string>) => promise<result<string, string>>,
}
type fetcher = {
  fetch: string => promise<result<string, string>>,
  clearCache: unit => unit,
}
type shellEnvEntry = {key: string, value: string}
type shellEnvConfig = {vars: array<shellEnvEntry>}
type shellBuilder = {buildEnvFilterConfig: ConfigTypes.shellEnv => shellEnvConfig}
type envFilter = {buildSafeEnv: (option<shellEnvConfig>, dict<string>) => dict<string>}

type fileSystem = {
  readFile: (string, ~options: readFileOptions=?) => promise<string>,
  writeFile: (string, string, ~options: writeFileOptions=?) => promise<unit>,
  mkdir: (string, ~options: mkdirOptions=?) => promise<string>,
  rm: (string, ~options: rmOptions=?) => promise<unit>,
  cp: (string, string, ~options: cpOptions=?) => promise<unit>,
  readdir: (string, ~options: readdirOptions=?) => promise<array<string>>,
  fileExists: string => promise<bool>,
  stat: string => promise<statResult>,
  lstat: string => promise<lstatResult>,
  realpath: string => promise<string>,
  makeStagingDir: string => promise<string>,
}
type process = {
  cwd: unit => string,
  env: unit => dict<string>,
  argv: unit => array<string>,
  exit: int => unit,
  onSignal: (string, unit => unit) => unit,
  removeSignalListeners: unit => unit,
  homedir: unit => string,
}
type execResult = {stdout: string, stderr: string, status: option<int>, signalCode: option<string>, killed: bool}
type shellOptions = {cwd?: string, env?: dict<string>, encoding?: string, timeout?: int}
type shell = {
  execFileAsync: (string, ~args: array<string>=?, ~options: shellOptions=?) => promise<execResult>,
}
type path = {
  join: (string, string) => string,
  resolve: (string, string) => string,
  dirname: string => string,
  isAbsolute: string => bool,
  basename: (string, ~ext: string=?) => string,
}
type pathSecurity = {isWithinTree: (string, string, path, fileSystem) => promise<bool>}
type interactiveIO = {
  ask: string => promise<string>,
  askConfirm: (~question: string, ~defaultYes: bool=?) => promise<bool>,
  close: unit => unit,
}
type parsedArgs = {values: dict<string>, positionals: array<string>}
type argParser = {parse: (~args: array<string>, ~strict: bool, ~allowPositionals: bool) => result<parsedArgs, string>}
type hooks = {
  run: (
    ~config: ConfigTypes.config,
    ~projectRoot: string,
    ~hookType: hookType,
    ~shellConfig: option<ConfigTypes.shellConfig>,
    ~shell: shell,
    ~process: process,
    ~path: path,
    ~fs: fileSystem,
    ~scriptRoot: string=?,
    ~cwd: string=?,
    ~toolsAllowlist: option<array<string>>=?,
  ) => promise<result<hookResult, string>>,
}

type deps = {
  fs: fileSystem,
  path: path,
  process: process,
  shell: shell,
  interactiveIO: interactiveIO,
  argParser: argParser,
  yamlParser: yamlParser,
  ejs: ejs,
  fetcher: fetcher,
  pathSecurity: pathSecurity,
  shellBuilder: shellBuilder,
  envFilter: envFilter,
  hooks: hooks,
}
