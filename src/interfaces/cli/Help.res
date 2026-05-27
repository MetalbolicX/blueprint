let printGenerateOptions = (~includeDefaults: bool) => {
  if includeDefaults {
    Console.log("  --name <name>          Component/resource name (default: same as <class>)")
  } else {
    Console.log("  --name <name>          Component/resource name")
  }
  Console.log("  --force                Skip prompts and overwrite existing files")
  Console.log("  --output <dir>         Output directory (default: generated/)")
  Console.log("  --<key> <value>        Pass attributes to templates.")
  Console.log("                         Repeat the flag for multi-select prompts")
  Console.log("                         (e.g., --methods GET --methods POST).")
}

let printUsage = () => {
  Console.log("")
  Console.log("Usage: blueprint <command> [options]")
  Console.log("")
  Console.log("Commands:")
  Console.log("  init                   Create a .blueprint.yaml config in current directory")
  Console.log("  init --global          Create global config at ~/.config/blueprint/config.yaml")
  Console.log("  generate <class>       Generate files from a template")
  Console.log("  generator <action>     Manage generators (scaffold + future wizard actions)")
  Console.log("  template copy <name>   Install a template into the global registry")
  Console.log("  template list          Show globally installed templates")
  Console.log("  template remove <name> Uninstall a template from the global registry")
  Console.log("  help <command>         Show detailed help for a specific command")
  Console.log("")
  Console.log("Generate options:")
  printGenerateOptions(~includeDefaults=true)
  Console.log("")
  Console.log("Examples:")
  Console.log("  blueprint init")
  Console.log("  blueprint init --global")
  Console.log("  blueprint generate react-component --name Button --force")
  Console.log("  blueprint generate generator --name api-route")
  Console.log("  blueprint generator list api-route")
  Console.log("  blueprint generate express-endpoint --name User --routePath /users \\")
  Console.log("    --methods GET --methods POST --methods PUT --methods DELETE")
  Console.log("  blueprint template copy express-endpoint")
  Console.log("  blueprint template list")
  Console.log("  blueprint help generate")
}

let printHelpFor = (command: string) => {
  switch command {
  | "generate" =>
    Console.log("")
    Console.log("Usage: blueprint generate <class> [options]")
    Console.log("")
    Console.log("Generate files from a template. <class> is the template name")
    Console.log("(e.g., express-endpoint, react-component, go-handler).")
    Console.log("")
    Console.log("Arguments:")
    Console.log("  <class>               Template classification name")
    Console.log("")
    Console.log("Options:")
    printGenerateOptions(~includeDefaults=false)
    Console.log("")
    Console.log("Examples:")
    Console.log("  blueprint generate express-endpoint --name Product --routePath /products")
    Console.log("  blueprint generate react-component --name Button --force")
    Console.log("  blueprint generate go-handler --name UserHandler --package handlers")

  | "init" =>
    Console.log("")
    Console.log("Usage: blueprint init [--global]")
    Console.log("")
    Console.log("Create a .blueprint.yaml configuration file.")
    Console.log("")
    Console.log("Options:")
    Console.log("  --global              Create global config at ~/.config/blueprint/config.yaml")
    Console.log("                        instead of local .blueprint.yaml")
    Console.log("")
    Console.log("Examples:")
    Console.log("  blueprint init")
    Console.log("  blueprint init --global")

  | "template" =>
    Console.log("")
    Console.log("Usage: blueprint template <action> [name]")
    Console.log("")
    Console.log("Manage globally installed templates.")
    Console.log("")
    Console.log("Actions:")
    Console.log("  copy <name>           Install a template from _templates/ into")
    Console.log("                        ~/.config/blueprint/templates/")
    Console.log("  list                  List installed global templates")
    Console.log("  remove <name>         Remove a template from global registry")
    Console.log("")
    Console.log("Examples:")
    Console.log("  blueprint template copy express-endpoint")
    Console.log("  blueprint template list")
    Console.log("  blueprint template remove express-endpoint")

  | "generator" =>
    Console.log("")
    Console.log("Usage: blueprint generator <action> <name>")
    Console.log("")
    Console.log("Manage an existing generator (wizard features are scaffolded in Slice 1).")
    Console.log("")
    Console.log("Actions:")
    Console.log("  list <name>            List prompts/templates for a generator (stub)")
    Console.log("  add-prompt <name>      Add prompt to manifest.yaml (stub)")
    Console.log("  add-file <name>        Add .ejs.t template file (stub)")
    Console.log("")
    Console.log("Examples:")
    Console.log("  blueprint generate generator --name mygen")
    Console.log("  blueprint generator list mygen")

  | "help" =>
    printUsage()

  | _ =>
    Console.log("Unknown command: " ++ command)
    Console.log("Available commands: init, generate, generator, template, help")
  }
}