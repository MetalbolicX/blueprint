// ShellQueue: collect shell directives from a template into an ordered shellCommand array.
// Handles Fetch (passthrough), Tool (lookup by name in shellConfig), Script (lookup + path resolve).

open Template

let findToolByName: (array<Config.shellTool>, string) => option<Config.shellTool> = (
  tools,
  name,
) => {
  tools->Array.find(tool => tool.name == name)
}

let findScriptByName: (array<Config.scriptDef>, string) => option<Config.scriptDef> = (
  scripts,
  name,
) => {
  scripts->Array.find(script => script.name == name)
}

let collectTemplate: (
  template,
  option<Config.shellConfig>,
  ~actionfolder: string,
  ~path: Ports.path,
  ~process: Ports.process,
) => result<array<shellCommand>, string> = (
  template,
  shellConfig,
  ~actionfolder,
  ~path,
  ~process,
) => {
  let commands: array<shellCommand> = []
  let errorRef: ref<option<string>> = ref(None)

  template.directives->Array.forEach(d => {
    switch errorRef.contents {
    | Some(_) => ()
    | None =>
      switch d {
      | Fetch(url) => {
          let _ = commands->Array.push({target: Fetch(url), sourcePath: template.sourcePath})
        }
      | Tool(name) => {
          let tools = switch shellConfig {
          | Some(cfg) => cfg.tools->Option.getOr([])
          | None => []
          }
          switch findToolByName(tools, name) {
          | Some(toolDef) =>
            let _ = commands->Array.push({
              target: ToolCall({name, toolDef, sourcePath: template.sourcePath}),
              sourcePath: template.sourcePath,
            })
          | None =>
            errorRef.contents = Some(
              "Tool not found: " ++ name ++ " (template: " ++ template.sourcePath ++ ")",
            )
          }
        }
      | Script(name) => {
          let scripts = switch shellConfig {
          | Some(cfg) => cfg.scripts->Option.getOr([])
          | None => []
          }
          switch findScriptByName(scripts, name) {
          | Some(scriptDef) =>
            let baseDir = if path.isAbsolute(actionfolder) {
              actionfolder
            } else {
              path.resolve(process.cwd(), actionfolder)
            }
            let resolvedPath = path.isAbsolute(scriptDef.path)
              ? scriptDef.path
              : path.join(baseDir, scriptDef.path)
            let _ = commands->Array.push({
              target: ScriptFile(resolvedPath),
              sourcePath: template.sourcePath,
            })
          | None =>
            errorRef.contents = Some(
              "Script not found: " ++ name ++ " (template: " ++ template.sourcePath ++ ")",
            )
          }
        }
      | _ => ()
      }
    }
  })

  switch errorRef.contents {
  | Some(message) => Error(message)
  | None => Ok(commands)
  }
}