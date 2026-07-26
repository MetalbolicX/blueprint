// Generate — run a generator with the given classification and name
let runGenerate: (
  ~deps: Ports.deps,
  ~fs: Ports.fileSystem,
  ~path: Ports.path,
  ~classification: string,
  ~name: string,
  ~force: bool,
  ~outputDir: string,
  ~cliAttributes: dict<Context.attrValue>,
) => promise<unit> = async (
  ~deps,
  ~fs,
  ~path,
  ~classification,
  ~name,
  ~force,
  ~outputDir,
  ~cliAttributes,
) => {
  let ctx = await ConfigContext.loadConfigContext(~deps, ~fs, ~path)

  switch Config.validateMergedConfig(ctx.merged) {
  | Error(e) => {
      Console.error("Error: " ++ e)
      deps.process.exit(1)
    }
  | Ok() => {
      // Discovery runs AFTER validation (test asserts invalid config exits before discovery)
      let projectPaths = ["_templates", "templates", "generators"]
      let allPaths = Utils.buildGenerateSearchPaths(
        ~deps,
        ~projectPaths,
        ~registry=ctx.globalConfig.registry,
        ~globalTemplates=ctx.merged.templates,
      )
      let generators = await Discovery.discover(~fs, ~path, ~yamlParser=deps.yamlParser, ~searchPaths=allPaths, ())

      switch Discovery.findByClassification(generators, classification) {
      | None => {
          Console.error(
            "Error: generator not found for classification \"" ++ classification ++ "\"",
          )
          deps.process.exit(1)
        }
      | Some(generator) => {
          // Build effective config for Engine (using merged timeout)
          // Keep project hooks as-is but use merged timeout
          let effectiveConfig: Config.config = {
            output: ?ctx.projectConfig->Option.flatMap(c => c.output),
            dryRun: ?Some(ctx.merged.dryRun),
            hooks: ?Some({
              preGenerate: ?ctx.projectConfig->Option.flatMap(c => c.hooks)->Option.flatMap(
                h => h.preGenerate,
              ),
              postGenerate: ?ctx.projectConfig->Option.flatMap(c => c.hooks)->Option.flatMap(
                h => h.postGenerate,
              ),
              timeout: ctx.merged.timeout,
            }),
            shell: ?ctx.merged.shell,
          }

          let result = await Engine.run(
            ~generator,
            ~name,
            ~cliAttributes,
            ~outputDir,
            ~force,
            ~config=effectiveConfig,
            ~deps,
          )

          switch result {
          | Error(e) => {
              Console.error("Error: " ++ e.message)
              switch e.partialCommit {
              | Some(files) if files->Array.length > 0 =>
                Console.error("Partially committed files: " ++ files->Array.join(", "))
              | _ => ()
              }
              switch e.catastrophic {
              | Some(true) =>
                switch e.failedRollbackFiles {
                | Some(failed) if failed->Array.length > 0 =>
                  Console.error(
                    "WARNING: Could not rollback these files: " ++ failed->Array.join(", "),
                  )
                | _ => ()
                }
                Console.error(
                  "Catastrophic failure — output directory may be in an inconsistent state",
                )
              | _ => ()
              }
              deps.process.exit(1)
            }
          | Ok(r) => {
              switch r.shellErrors {
              | Some(errs) if errs->Array.length > 0 =>
                errs->Array.forEach(err => Console.warn("Shell warning: " ++ err))
              | _ => ()
              }
              Console.log(
                "Blueprint: generated " ++
                Int.toString(r.filesCreated) ++
                " file(s), " ++
                Int.toString(r.commandsExecuted) ++
                " command(s)",
              )
            }
          }
        }
      }
    }
  }
}
