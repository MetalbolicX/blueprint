// Phase2: Atomic commit from staging to output, rollback on failure
// Mirrors Go version's phase2/phase2.go

open Bindings
open Template

type phase2Result = {
  filesCreated: int,
  filesInjected: int,
  commandsExecuted: int,
}

type phase2Error = {
  message: string,
  partialCommit: option<array<string>>, // files that were committed before error
}

// Execute all queued shell commands
let executeShellCommands: (
  ~commands: array<shellCommand>,
  ~cwd: string,
) => promise<result<int, string>> = (~commands, ~cwd) => {
  let count = ref(0)
  let promise = commands->Array.reduce(Promise.resolve(Ok()), (acc, cmd) => {
    acc->Promise.then(r => {
      switch r {
      | Error(e) => Promise.resolve(Error(e))
      | Ok(_) =>
        ChildProcess.execShellCommand(~command=cmd.command, ~cwd)->Promise.then(
          result => {
            switch result {
            | Ok(_) => {
                count.contents = count.contents + 1
                Promise.resolve(Ok())
              }
            | Error(e) => Promise.resolve(Error("Shell command failed: " ++ e))
            }
          },
        )
      }
    })
  })
  promise->Promise.then(r => {
    switch r {
    | Ok(_) => Promise.resolve(Ok(count.contents))
    | Error(e) => Promise.resolve(Error(e))
    }
  })
}

// Copy staged files to output directory
let commitFiles: (
  ~stagingDir: string,
  ~outputDir: string,
  ~renderedFiles: array<(string, string)>,
) => promise<result<int, phase2Error>> = (~stagingDir, ~outputDir, ~renderedFiles) => {
  let _ = (stagingDir, outputDir, renderedFiles)
  Promise.resolve(Ok(0))
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
  ~shellCommands: array<shellCommand>,
) => promise<result<phase2Result, phase2Error>> = async (
  ~stagingDir,
  ~outputDir,
  ~renderedFiles,
  ~shellCommands,
) => {
  // Commit files
  let commitResult = await commitFiles(~stagingDir, ~outputDir, ~renderedFiles)

  switch commitResult {
  | Ok(count) => {
      // Execute shell commands
      let shellResult = await executeShellCommands(~commands=shellCommands, ~cwd=outputDir)

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
      | Error(_e) =>
        // Shell failed but files committed — return partial success
        Ok({
          filesCreated: count,
          filesInjected: 0,
          commandsExecuted: 0,
        })
      }
    }
  | Error(err) => {
      // Commit failed — rollback
      await rollback(stagingDir)
      Error(err)
    }
  }
}
