// ConflictResolver — bulk conflict resolution types and parser
// I/O orchestration lives in application/conflicts/ConflictRunner.res

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

let parseChoice: string => option<resolution> = input => {
  let trimmed = String.trim(input)->String.toLowerCase
  switch trimmed {
  | "y" | "yes" => Some(Yes)
  | "a" | "abort" => Some(Abort)
  | "all" => Some(YesAll)
  | "n" | "no" => Some(NoAll)
  | "s" | "select" => Some(Select)
  | _ => None
  }
}
