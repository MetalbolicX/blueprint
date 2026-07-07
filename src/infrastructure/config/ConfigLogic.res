// ConfigLogic.res
open ConfigTypes

// Merge project + global configs. Project values take precedence.
let mergeConfig: (~global: globalConfig, ~project: option<config>) => mergedConfig = (
  ~global,
  ~project,
) => {
  let effectiveTimeout = switch project {
  | Some(p) =>
    switch p.hooks {
    | Some(h) =>
      switch h.timeout {
      | Some(t) => t
      | None => global.timeout
      }
    | None => global.timeout
    }
  | None => global.timeout
  }
  let effectiveShell = switch project {
  | Some(p) => p.shell
  | None => None
  }
  let effectiveDryRun = switch project {
  | Some(p) => p.dryRun
  | None => None
  }
  {
    templates: global.templates,
    forceOverwrite: global.forceOverwrite,
    dryRun: effectiveDryRun->Option.getOr(global.dryRun),
    timeout: effectiveTimeout,
    defaultAttributes: global.defaultAttributes,
    shell: ?effectiveShell,
  }
}

// Validate merged config for fail-fast enforcement
// Returns Ok if config is valid, Error(message) if not
let validateMergedConfig: mergedConfig => result<unit, string> = cfg => {
  if cfg.timeout < 1 {
    Error("timeout must be >= 1, got " ++ Int.toString(cfg.timeout))
  } else {
    switch cfg.shell {
    | Some(s) if s.enabled && s.tools->Option.isNone =>
      Error("shell.enabled=true requires tools to be defined")
    | _ => Ok()
    }
  }
}
