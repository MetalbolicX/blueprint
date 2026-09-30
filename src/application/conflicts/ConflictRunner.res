// ConflictRunner — I/O orchestration for conflict resolution.
// Pure types and parseChoice live in ConflictResolver (domain layer).
// This module handles the interactive prompt loop.

let promptBulkResolution: (
  ~io: Ports.interactiveIO,
  ~count: int,
) => promise<ConflictResolver.resolution> = (~io, ~count) => {
  let promptText =
    "\n" ++
    Int.toString(
      count,
    ) ++
    " file(s) already exist. Overwrite all? [y]es / [n]o / [s]elect / [a]bort:\n" ++
    "Type all to overwrite everything; a or abort stops with nothing written. "

  let rec loop = () => {
    io.ask(promptText)->Promise.then(answer => {
      switch ConflictResolver.parseChoice(answer) {
      | Some(r) => Promise.resolve(r)
      | None => loop()
      }
    })
  }
  loop()
}

let resolveConflicts: (
  ~io: Ports.interactiveIO,
  ~conflicts: array<ConflictResolver.fileConflict>,
  ~force: bool,
) => promise<result<array<ConflictResolver.conflictDecision>, string>> = (
  ~io,
  ~conflicts,
  ~force,
) => {
  if force {
    let decisions = conflicts->Array.map(c => {
      {
        ConflictResolver.sourcePath: c.sourcePath,
        targetPath: c.targetPath,
        overwrite: true,
      }
    })
    Promise.resolve(Ok(decisions))
  } else if Array.length(conflicts) == 0 {
    Promise.resolve(Ok([]))
  } else {
    promptBulkResolution(~io, ~count=Array.length(conflicts))->Promise.then(resolution => {
      switch resolution {
      | ConflictResolver.YesAll | ConflictResolver.Yes =>
        let decisions = conflicts->Array.map(c => {
          {
            ConflictResolver.sourcePath: c.sourcePath,
            targetPath: c.targetPath,
            overwrite: true,
          }
        })
        Promise.resolve(Ok(decisions))

      | ConflictResolver.NoAll =>
        let decisions = conflicts->Array.map(c => {
          {
            ConflictResolver.sourcePath: c.sourcePath,
            targetPath: c.targetPath,
            overwrite: false,
          }
        })
        Promise.resolve(Ok(decisions))

      | ConflictResolver.Abort => Promise.resolve(Error("Aborted by user"))

      | ConflictResolver.Select =>
        let decisions: array<ConflictResolver.conflictDecision> = []
        let rec loop = (idx: int, conflicts: array<ConflictResolver.fileConflict>) => {
          if idx >= Array.length(conflicts) {
            Promise.resolve(Ok(decisions))
          } else {
            switch conflicts[idx] {
            | Some(c) =>
              let rec askForDecision = (showFeedback: bool) => {
                let feedback = if showFeedback {
                  "Invalid choice. Enter y, n, or abort.\n"
                } else {
                  ""
                }
                io.ask(
                  feedback ++ "Overwrite " ++ c.targetPath ++ "? [y]es / [n]o / [a]bort: ",
                )->Promise.then(answer => {
                  switch ConflictResolver.parseChoice(answer) {
                  | Some(ConflictResolver.Yes) => {
                      let _ = decisions->Array.push({
                        ConflictResolver.sourcePath: c.sourcePath,
                        targetPath: c.targetPath,
                        overwrite: true,
                      })
                      loop(idx + 1, conflicts)
                    }
                  | Some(ConflictResolver.NoAll) => {
                      let _ = decisions->Array.push({
                        ConflictResolver.sourcePath: c.sourcePath,
                        targetPath: c.targetPath,
                        overwrite: false,
                      })
                      loop(idx + 1, conflicts)
                    }
                  | Some(ConflictResolver.Abort) => Promise.resolve(Error("Aborted by user"))
                  | _ => askForDecision(true)
                  }
                })
              }
              askForDecision(false)
            | None => Promise.resolve(Ok(decisions))
            }
          }
        }
        loop(0, conflicts)
      }
    })
  }
}
