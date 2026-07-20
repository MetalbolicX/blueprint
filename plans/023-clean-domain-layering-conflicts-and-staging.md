# Plan 023: Split ConflictResolver I/O out of domain; move makeStagingDir off the fileSystem port

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 64a81fa..HEAD -- src/domain/conflicts/ConflictResolver.res src/domain/ports/Ports.res src/infrastructure/adapters/NodeJsFileSystem.res src/infrastructure/adapters/DenoFileSystem.res src/application/pipeline/Staging.res src/application/pipeline/Phase1.res src/application/engine/EnginePhases.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `64a81fa`, 2026-07-20

## Why this matters

`ConflictResolver.res` lives under `src/domain/` but contains two functions (`promptBulkResolution` and `resolveConflicts`) that accept `~io: Ports.interactiveIO` — a side-effectful I/O port. The domain layer should hold pure types and logic only. Mixing I/O here makes it impossible to test the resolution logic without mocking a readline interface and obscures the architectural layering. Separating the I/O orchestration from the pure type definitions and `parseChoice` parser makes the domain layer genuinely pure and moves the interactive orchestration to the application layer where it belongs. This is a two-part plan: the second half extracts `makeStagingDir` from the `fileSystem` port, which is a staging/process concern unrelated to filesystem operations.

## Current state

- `src/domain/conflicts/ConflictResolver.res` — 120 lines. Contains:
  - **Pure types** (lines 4–21): `resolution`, `fileConflict`, `conflictDecision`
  - **Pure parser** (lines 24–34): `parseChoice: string => option<resolution>`
  - **I/O orchestration** (lines 37–56): `promptBulkResolution` — takes `~io: Ports.interactiveIO`, calls `io.ask` in a loop
  - **I/O orchestration** (lines 59–119): `resolveConflicts` — takes `~io: Ports.interactiveIO`, calls `promptBulkResolution` and `io.ask`

- `src/application/engine/EnginePhases.res:20` — the only production caller of `ConflictResolver.resolveConflicts`:
  ```rescript
  let conflictResult = await ConflictResolver.resolveConflicts(
    ~io,
    ~conflicts=p0.conflicts->Array.map(c => {
      {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath}
    }),
    ~force,
  )
  ```

- `src/domain/ports/Ports.res:29` — `makeStagingDir: unit => string` sits in `fileSystem`:
  ```rescript
  type fileSystem = {
    ...
    makeStagingDir: unit => string,
    ...
  }
  ```

- `src/infrastructure/adapters/NodeJsFileSystem.res:58` — implements it via `NodeJs.Os.makeStagingDir`:
  ```rescript
  makeStagingDir: NodeJs.Os.makeStagingDir,
  ```

- `src/infrastructure/adapters/DenoFileSystem.res:46` — implements it via `makeTempDirSync`:
  ```rescript
  makeStagingDir: makeTempDirSync,
  ```

- `src/application/pipeline/Staging.res:5` — sole production consumer:
  ```rescript
  let stagingDir = fs.makeStagingDir()
  ```

- `src/application/pipeline/Phase1.res:103` — calls `Staging.create(~fs)`:
  ```rescript
  switch await Staging.create(~fs) {
  ```

- `test/ConflictResolver_test.res` — tests use `ConflictResolver.parseChoice` (pure) and `ConflictResolver.resolveConflicts` (I/O). The I/O tests use a `mockIo` record.

- `rescript.json` — in-source compilation, no path aliases. Source dirs: `src` and `test`. Moving a file means the module name changes based on its directory path.

## Commands you will need

| Purpose   | Command                  | Expected on success       |
|-----------|--------------------------|---------------------------|
| Build     | `pnpm build`             | exit 0                    |
| Tests     | `pnpm res:test`          | all pass                  |

## Scope

**In scope**:
- `src/domain/conflicts/ConflictResolver.res` — remove `promptBulkResolution` and `resolveConflicts`, keep types + `parseChoice`
- `src/application/conflicts/ConflictRunner.res` — NEW file, receives the moved I/O functions
- `src/application/engine/EnginePhases.res` — update import of `resolveConflicts` from `ConflictResolver` to `ConflictRunner`
- `test/ConflictResolver_test.res` — update test imports for moved functions
- `src/domain/ports/Ports.res` — remove `makeStagingDir` from `fileSystem`
- `src/infrastructure/adapters/NodeJsFileSystem.res` — remove `makeStagingDir` field
- `src/infrastructure/adapters/DenoFileSystem.res` — remove `makeStagingDir` field
- `src/application/pipeline/Staging.res` — accept `~tmpDir: string` parameter instead of calling `fs.makeStagingDir()`
- `src/application/pipeline/Phase1.res` — pass a tmpDir to `Staging.create`

**Out of scope**:
- Changing the `resolution` type or `parseChoice` logic
- Refactoring the conflict detection in `Phase0.res`
- Any changes to how `Staging.writeStagedFile` or `Staging.removeStagingDir` work

## Steps

### Step 1: Create `src/application/conflicts/ConflictRunner.res` with moved I/O functions

Create the directory `src/application/conflicts/` and the file `ConflictRunner.res` inside it. Move `promptBulkResolution` and `resolveConflicts` from `ConflictResolver.res` into this new module. The new module imports `ConflictResolver` for its types. The function signatures remain identical except the module qualification changes.

```rescript
// ConflictRunner.res — I/O orchestration for conflict resolution
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
    ) ++ " file(s) already exist. Overwrite all? [y]es / [n]o / [s]elect / [a]bort: "

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
) => promise<result<array<ConflictResolver.conflictDecision>, string>> = (~io, ~conflicts, ~force) => {
  if force {
    let decisions = conflicts->Array.map(c => {
      {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath, overwrite: true}
    })
    Promise.resolve(Ok(decisions))
  } else if Array.length(conflicts) == 0 {
    Promise.resolve(Ok([]))
  } else {
    promptBulkResolution(~io, ~count=Array.length(conflicts))->Promise.then(resolution => {
      switch resolution {
      | ConflictResolver.YesAll | ConflictResolver.Yes =>
        let decisions = conflicts->Array.map(c => {
          {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath, overwrite: true}
        })
        Promise.resolve(Ok(decisions))

      | ConflictResolver.NoAll =>
        let decisions = conflicts->Array.map(c => {
          {ConflictResolver.sourcePath: c.sourcePath, targetPath: c.targetPath, overwrite: false}
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
              io.ask(
                "Overwrite " ++ c.targetPath ++ "? [y]es / [n]o: ",
              )->Promise.then(answer => {
                let overwrite = switch ConflictResolver.parseChoice(answer) {
                | Some(ConflictResolver.Yes) => true
                | _ => false
                }
                let _ = decisions->Array.push({
                  ConflictResolver.sourcePath: c.sourcePath,
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
```

**Verify**: `pnpm build` → exits 0 (new module compiles; old functions still exist in ConflictResolver.res — no conflict yet)

### Step 2: Remove I/O functions from `ConflictResolver.res`

In `src/domain/conflicts/ConflictResolver.res`, delete `promptBulkResolution` (lines 37–56) and `resolveConflicts` (lines 58–119). Keep only the type definitions (lines 4–21) and `parseChoice` (lines 24–34).

The file should end up as:

```rescript
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
  | "a" | "all" => Some(YesAll)
  | "n" | "no" | "q" => Some(NoAll)
  | "s" | "select" => Some(Select)
  | "abort" => Some(Abort)
  | _ => None
  }
}
```

**Verify**: `pnpm build` → will FAIL (EnginePhases.res still calls `ConflictResolver.resolveConflicts`). This is expected.

### Step 3: Update `EnginePhases.res` to import from `ConflictRunner`

In `src/application/engine/EnginePhases.res`, change line 20 from:

```rescript
let conflictResult = await ConflictResolver.resolveConflicts(
```

to:

```rescript
let conflictResult = await ConflictRunner.resolveConflicts(
```

**Verify**: `pnpm build` → exits 0

### Step 4: Update `test/ConflictResolver_test.res`

The test file calls `ConflictResolver.resolveConflicts` directly (lines 76, 110). Update these references to `ConflictRunner.resolveConflicts`. The `ConflictResolver.parseChoice` calls remain unchanged.

Line 76: change `ConflictResolver.resolveConflicts` → `ConflictRunner.resolveConflicts`
Line 110: change `ConflictResolver.resolveConflicts` → `ConflictRunner.resolveConflicts`

**Verify**: `pnpm res:test` → all tests pass

### Step 5: Remove `makeStagingDir` from `Ports.fileSystem`

In `src/domain/ports/Ports.res`, remove line 29:
```rescript
  makeStagingDir: unit => string,
```

**Verify**: `pnpm build` → will FAIL (adapters and Staging.res reference it). Expected.

### Step 6: Remove `makeStagingDir` from both filesystem adapters

In `src/infrastructure/adapters/NodeJsFileSystem.res`, remove line 58:
```rescript
  makeStagingDir: NodeJs.Os.makeStagingDir,
```

In `src/infrastructure/adapters/DenoFileSystem.res`, remove line 46:
```rescript
  makeStagingDir: makeTempDirSync,
```

**Verify**: `pnpm build` → will FAIL (Staging.res still calls `fs.makeStagingDir()`). Expected.

### Step 7: Update `Staging.res` to accept a `~tmpDir` parameter

Change `Staging.create` to accept `~tmpDir: string` instead of calling `fs.makeStagingDir()`:

```rescript
let create: (~tmpDir: string, ~fs: Ports.fileSystem) => promise<result<string, string>> = async (~tmpDir, ~fs) => {
  try {
    let _ = await fs.mkdir(tmpDir, ~options={recursive: true})
    Ok(tmpDir)
  } catch {
  | JsExn(obj) =>
    let msg = switch JsExn.message(obj) {
    | Some(m) => m
    | None => "mkdir failed"
    }
    Error(msg)
  }
}
```

**Verify**: `pnpm build` → will FAIL (Phase1.res calls `Staging.create(~fs)` without `~tmpDir`). Expected.

### Step 8: Update `Phase1.res` call site

In `src/application/pipeline/Phase1.res`, the call to `Staging.create` at line 103 needs to produce a temp directory path. Use `NodeJs.Os.makeStagingDir()` (the same underlying function) directly in Phase1, passing the result as `~tmpDir`:

```rescript
let tmpDir = NodeJs.Os.makeStagingDir()
switch await Staging.create(~tmpDir, ~fs) {
```

This is acceptable because Phase1 is in the application layer and orchestrates staging — it's the right place to decide where temp files go. The `NodeJs.Os` binding is an infrastructure detail, but Phase1 already imports infrastructure-adjacent modules. Alternatively, if you want to keep Phase1 decoupled, add `~tmpDir: string` to Phase1's own signature and let the caller (EnginePhases/EngineOrchestrator) supply it. Choose the simpler approach (direct call) unless you want the additional indirection.

**Verify**: `pnpm build` → exits 0

### Step 9: Run full test suite and clean up stale artifacts

Delete any stale `.res.mjs` artifacts at old paths:
```bash
rm -f src/domain/conflicts/ConflictResolver.promptBulkResolution.res.mjs
rm -f src/domain/conflicts/ConflictResolver.resolveConflicts.res.mjs
```

(These are unlikely to exist with in-source compilation, but safe to attempt.)

**Verify**: `pnpm res:test` → all tests pass

## Test plan

- Existing `test/ConflictResolver_test.res` tests for `parseChoice` continue unchanged (pure, domain layer).
- Existing `test/ConflictResolver_test.res` tests for `resolveConflicts` updated to call `ConflictRunner.resolveConflicts` — same mock Io, same assertions.
- No new test file needed; the moved functions keep their existing test coverage.
- `Staging.create` change is covered by existing Phase1 integration tests that exercise the full pipeline.

## Done criteria

- [ ] `pnpm build` exits 0
- [ ] `pnpm res:test` exits 0
- [ ] `src/domain/conflicts/ConflictResolver.res` contains only types + `parseChoice` (no `~io` parameters)
- [ ] `src/application/conflicts/ConflictRunner.res` exists and contains `promptBulkResolution` + `resolveConflicts`
- [ ] `grep -n "Ports.interactiveIO" src/domain/conflicts/ConflictResolver.res` returns no matches
- [ ] `grep -n "makeStagingDir" src/domain/ports/Ports.res` returns no matches
- [ ] `grep -n "makeStagingDir" src/infrastructure/adapters/NodeJsFileSystem.res` returns no matches
- [ ] `grep -n "makeStagingDir" src/infrastructure/adapters/DenoFileSystem.res` returns no matches
- [ ] No files outside the in-scope list are modified (`git status`)

## STOP conditions

- The code at the locations in "Current state" doesn't match the excerpts (the codebase has drifted since this plan was written).
- `pnpm build` fails after Step 3 or Step 8 with an error not described above.
- The fix requires touching files outside the in-scope list.
- `EnginePhases.res` has additional callers of ConflictResolver I/O functions beyond `resolveConflicts` (grep to confirm).
- Phase1.res already receives `tmpDir` as a parameter (plan's Step 8 assumption is wrong).

## Maintenance notes

- The `ConflictRunner` module name follows the existing `application/` convention: modules under `src/application/` are orchestration over ports.
- Future work: consider whether `ConflictRunner` should be injected into `EnginePhases.runPhase0` as a dependency rather than being called directly — but that's a larger DI refactor out of scope here.
- The `makeStagingDir` extraction means the port no longer has a method that returns a platform-specific temp path. `Staging.create` now receives the path explicitly, which is cleaner for testing (tests can pass a known path).
- If a Deno port is added in the future, the caller of `Staging.create` must supply the Deno temp path — the adapter no longer hides this detail.
