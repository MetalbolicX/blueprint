// Hooks — pre/post generate lifecycle hook execution
// Mirrors Go version's hooks/hooks.go

open Bindings

type hookType = PreGenerate | PostGenerate

type hookResult = {
  hookType: hookType,
  output: string,
  exitCode: int,
}

// Parse hook command string into interpreter + args
// e.g. "bash scripts/validate.sh" -> ["bash", "scripts/validate.sh"]
let parseCommand: string => (string, string) = cmd => {
  let parts = cmd->String.split(" ")
  let interpreter = switch parts[0] {
  | Some(p) => p
  | None => "bash"
  }
  let args = {
    let sliced = parts->Array.slice(~start=1)
    sliced->Array.join(" ")
  }
  (interpreter, args)
}

// Execute a single hook
let executeHook: (
  ~command: string,
  ~cwd: string,
  ~timeout: int,
) => promise<result<hookResult, string>> = async (~command, ~cwd, ~timeout) => {
  let (interpreter, args) = parseCommand(command)

  try {
    let fullCmd = interpreter ++ " " ++ args

    let result = await ChildProcess.exec(
      fullCmd,
      ~options={
        cwd,
        shell: true,
        timeout,
        encoding: "utf8",
      },
    )

    let exitCode = switch result.status {
    | Some(code) => code
    | None => 0
    }

    if exitCode == 0 {
      Ok({hookType: PreGenerate, output: result.stdout, exitCode})
    } else {
      Error("Hook exited with code " ++ Int.toString(exitCode) ++ ": " ++ result.stderr)
    }
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => "Hook execution failed: " ++ m
    | None => "Hook execution failed"
    }
    Error(msg)
  }
}

// Execute pre_generate and post_generate hooks
let run: (~config: Config.config, ~cwd: string) => promise<result<unit, string>> = async (
  ~config,
  ~cwd,
) => {
  let timeout = switch config.hooks {
  | Some(h) =>
    switch h.timeout {
    | Some(t) => t * 1000 // Convert seconds to ms
    | None => 5000
    }
  | None => 5000
  }

  // Run pre_generate hook
  let preResult: result<unit, string> = switch config.hooks {
  | Some(h) =>
    switch h.preGenerate {
    | Some(cmd) => {
        let result = await executeHook(~command=cmd, ~cwd, ~timeout)
        switch result {
        | Ok(_) => Ok()
        | Error(e) => Error("pre_generate hook failed: " ++ e)
        }
      }
    | None => Ok()
    }
  | None => Ok()
  }

  switch preResult {
  | Error(_) => preResult
  | Ok() => {
      // Run post_generate hook
      let postResult: result<unit, string> = switch config.hooks {
      | Some(h) =>
        switch h.postGenerate {
        | Some(cmd) => {
            let result = await executeHook(~command=cmd, ~cwd, ~timeout)
            switch result {
            | Ok(_) => Ok()
            | Error(e) => Error("post_generate hook failed: " ++ e)
            }
          }
        | None => Ok()
        }
      | None => Ok()
      }

      postResult
    }
  }
}
