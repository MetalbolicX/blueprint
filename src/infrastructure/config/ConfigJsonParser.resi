// ConfigJsonParser.resi
open ConfigTypes

let parseTemplateSource: JSON.t => option<templateSource>
let parseRegistry: JSON.t => array<templateSource>
let parseTemplates: JSON.t => array<string>
let parseDefaultAttributes: JSON.t => dict<string>
let parseHookCommand: JSON.t => option<hookCommand>
let parseHooks: JSON.t => option<hooksConfig>
let parseHooksResult: JSON.t => result<option<hooksConfig>, string>
let parseShellTool: JSON.t => option<shellTool>
let parseScriptDef: JSON.t => option<scriptDef>
let parseShellEnv: JSON.t => option<shellEnv>
let parseShellConfig: JSON.t => option<shellConfig>
