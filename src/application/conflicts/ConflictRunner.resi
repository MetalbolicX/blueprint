// ConflictRunner.resi

let resolveConflicts: (
  ~io: Ports.interactiveIO,
  ~conflicts: array<ConflictResolver.fileConflict>,
  ~force: bool,
) => promise<result<array<ConflictResolver.conflictDecision>, string>>
