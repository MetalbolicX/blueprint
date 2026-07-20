type resolution =
  | YesAll
  | Yes
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
