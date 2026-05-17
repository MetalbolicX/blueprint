// ConflictResolver — bulk conflict resolution (y/n/s/a)
// When output files already exist, user chooses how to handle

type resolution =
  | YesAll // overwrite all
  | NoAll // skip all
  | Select // choose per file
  | Abort // abort entire operation

type fileConflict = {
  sourcePath: string,
  targetPath: string,
}

// Result of conflict resolution per file
type conflictDecision = {
  sourcePath: string,
  targetPath: string,
  overwrite: bool,
}

// Parse single-character resolution from user input
let parseChoice: string => option<resolution> = input => {
  let trimmed = String.trim(input)->String.toLowerCase
  switch trimmed {
  | "y" | "yes" | "a" | "all" => Some(YesAll)
  | "n" | "no" | "q" => Some(NoAll)
  | "s" | "select" => Some(Select)
  | "abort" => Some(Abort)
  | _ => None
  }
}

// Show conflict prompt and get bulk resolution
let promptBulkResolution: (
  ~rl: Bindings.Readline.readlineInterface,
  ~count: int,
) => promise<resolution> = (~rl, ~count) => {
  let promptText =
    "\n" ++
    Int.toString(
      count,
    ) ++ " file(s) already exist. Overwrite all? [y]es / [n]o / [s]elect / [a]bort: "

  let rec loop = () => {
    rl.question(promptText)->Promise.then(answer => {
      switch parseChoice(answer) {
      | Some(r) => Promise.resolve(r)
      | None => loop()
      }
    })
  }
  loop()
}

// Resolve conflicts for a list of files
let resolveConflicts: (
  ~rl: Bindings.Readline.readlineInterface,
  ~conflicts: array<fileConflict>,
  ~force: bool,
) => promise<result<array<conflictDecision>, string>> = (~rl, ~conflicts, ~force) => {
  if force {
    // Force mode: overwrite all
    let decisions = conflicts->Array.map(c => {
      {sourcePath: c.sourcePath, targetPath: c.targetPath, overwrite: true}
    })
    Promise.resolve(Ok(decisions))
  } else if Array.length(conflicts) == 0 {
    Promise.resolve(Ok([]))
  } else {
    promptBulkResolution(~rl, ~count=Array.length(conflicts))->Promise.then(resolution => {
      switch resolution {
      | YesAll =>
        let decisions = conflicts->Array.map(c => {
          {sourcePath: c.sourcePath, targetPath: c.targetPath, overwrite: true}
        })
        Promise.resolve(Ok(decisions))

      | NoAll =>
        let decisions = conflicts->Array.map(c => {
          {sourcePath: c.sourcePath, targetPath: c.targetPath, overwrite: false}
        })
        Promise.resolve(Ok(decisions))

      | Abort => Promise.resolve(Error("Aborted by user"))

      | Select =>
        // Ask about each file individually
        let decisions: array<conflictDecision> = []
        let rec loop = (idx: int, conflicts: array<fileConflict>) => {
          if idx >= Array.length(conflicts) {
            Promise.resolve(Ok(decisions))
          } else {
            switch conflicts[idx] {
            | Some(c) =>
              rl.question(
                "Overwrite " ++ c.targetPath ++ "? [y]es / [n]o: ",
              )->Promise.then(answer => {
                let overwrite = switch parseChoice(answer) {
                | Some(YesAll) | Some(NoAll) | None => false
                | _ => true
                }
                let _ = decisions->Array.push({
                  sourcePath: c.sourcePath,
                  targetPath: c.targetPath,
                  overwrite,
                })
                loop(idx + 1, conflicts)
              })
            | None => Promise.resolve(Ok(decisions))
            }
          }
        }
        loop(0, conflicts)
      }
    })
  }
}
