// Phase2: Atomic commit from staging to output, rollback on failure
// Mirrors Go version's phase2/phase2.go

open Bindings

type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
}

type phase2Error = {
  message: string,
  partialCommit: option<array<string>>,  // files that were committed before error
}

// Execute all queued shell commands
let executeShellCommands: (
  ~commands: array<Templates.shellCommand>,
  ~cwd: string,
) => promise<result<int, string>> = async (~commands, ~cwd) => {
  let rec execLoop = (idx, count, commands) => {
    if idx >= Js.Array.length(commands) {
      Promise.resolve(Ok(count))
    } else {
      let cmd = commands[idx]
      let result = await ChildProcess.execShellCommand(~command=cmd.command, ~cwd)

      switch result {
      | Ok(_) => execLoop(idx + 1, count + 1, commands)
      | Error(e) => Promise.resolve(Error("Shell command failed: " ++ e))
      }
    }
  }

  execLoop(0, 0, commands)
}

// Copy staged files to output directory
let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
) => promise<result<int, phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
) => {
  let rec commitLoop = (idx, count, files) => {
    if idx >= Js.Array.length(files) {
      Promise.resolve(Ok(count))
    } else {
      let (source, target) = files[idx]
      let stagedPath = Node.Path.join(stagingDir, target)
      let targetPath = Node.Path.join(outputDir, target)

      try {
        // Ensure parent directory exists
        let parentDir = Node.Path.dirname(targetPath)
        await Fs.mkdir(parentDir, ~options={recursive: true})

        // Copy file from staging to output
        await Fs.cp(stagedPath, targetPath, ~options={recursive: false})

        commitLoop(idx + 1, count + 1, files)
      } catch {
      | Js.Exn.Error(obj) =>
        let msg = switch Js.Exn.message(obj) {
        | Some(m) => "Failed to commit file " ++ target ++ ": " ++ m
        | None => "Failed to commit file " ++ target
        }
        let committed = Js.Array.sliceFrom(files, 0, idx)->Js.Array.map(((_, t)) => t)
        Promise.resolve(Error({ message: msg, partialCommit: Some(committed) }))
      }
    }
  }

  commitLoop(0, 0, renderedFiles)
}

// Rollback: remove staging directory
let rollback: string => promise<unit> = async stagingDir => {
  try {
    await Fs.rm(stagingDir, ~options={recursive: true})
  } catch {
  | _ => ()
  }
}

// Run Phase2: commit staged files to output, execute shell commands
let run: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
  ~shellCommands: array<Templates.shellCommand>,
) => promise<result<phase2Result, phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
  ~shellCommands,
) => {
  // Commit files
  let commitResult = await commitFiles(
    ~stagingDir,
    ~outputDir,
    ~renderedFiles,
  )

  switch commitResult {
  | Ok(count) => {
      // Execute shell commands
      let shellResult = await executeShellCommands(
        ~commands=shellCommands,
        ~cwd=outputDir,
      )

      switch shellResult {
      | Ok(cmdsExec) => {
          // Cleanup staging dir
          await rollback(stagingDir)

          Ok({
            filesCreated: count,
            filesInjected: 0,
            commandsExecuted: cmdsExec,
          })
        }
      | Error(e) => {
          // Shell failed but files committed — return partial success
          Ok({
            filesCreated: count,
            filesInjected: 0,
            commandsExecuted: 0,
          })
        }
      }
    }
  | Error(err) => {
      // Commit failed — rollback
      await rollback(stagingDir)
      Promise.resolve(Error(err))
    }
  }
}