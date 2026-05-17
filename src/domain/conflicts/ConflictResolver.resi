type resolution =
  | YesAll
  | NoAll
  | Select
  | Abort

type fileConflict = {
  sourcePath: string,
  targetPath: string,
}

type conflictDecision = {
  sourcePath: string,
  targetPath: string,
  overwrite: bool,
}

let parseChoice: string => option<resolution>

let resolveConflicts: (
  ~rl: Bindings.Readline.readlineInterface,
  ~conflicts: array<fileConflict>,
  ~force: bool,
) => promise<result<array<conflictDecision>, string>>
