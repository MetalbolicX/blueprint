// InitGlobal — scaffold ~/.config/blueprint/config.yaml
let runInitGlobal: (~deps: Ports.deps) => promise<unit> = async (~deps) => {
  let homeDir = deps.process.homedir()
  let configDir = deps.path.join(deps.path.join(homeDir, ".config"), "blueprint")
  let configPath = deps.path.join(configDir, "config.yaml")

  // Check if global config already exists
  let exists = await deps.fs.fileExists(configPath)
  if exists {
    Console.error("Error: Global config already exists at " ++ configPath)
    deps.process.exit(1)
  } else {
    // Create the directory if it doesn't exist
    let dirExists = await deps.fs.fileExists(configDir)
    if !dirExists {
      let _ = await deps.fs.mkdir(configDir, ~options={recursive: true})
    }
    // WS4: `allow_dangerous_commands` removed from the bootstrapped config —
    // ExecPolicy (WS2) is the single authority over shell command safety.
    let content = "# Global Blueprint configuration\n# Loaded from ~/.config/blueprint/config.yaml\n\ntemplates: []\nforce_overwrite: false\ndry_run: false\ntimeout: 5\ndefault_attributes: {}\nregistry: []\n"
    let _ = await deps.fs.writeFile(configPath, content)
    Console.log("Scaffolded global config at " ++ configPath)
  }
}
