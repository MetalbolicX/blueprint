# Plan 012: Parallelize file commit and rollback in Commit.res

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/application/pipeline/Commit.res`
> If Commit.res changed significantly, read the current version and
> adjust line references before editing.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

Both `commitFiles` and `rollbackOutput` in Commit.res use sequential
`Array.reduce(Promise.resolve(), async (acc, ...) => { let _ = await acc; ... })`
chains. Each file commit requires 4-5 async I/O operations (isWithinTree,
fileExists, mkdir, cp) — serialized per file. For G generators creating
N files, commit time = N × latency of sequential ops. Parallelizing
independent file commits via `Promise.all` reduces wall-clock time to
roughly the slowest single file's latency.

## Current state

**File**: `src/application/pipeline/Commit.res`

`commitFiles` (lines 67-107):
```rescript
let _ = await renderedFiles->Array.reduce(
  Promise.resolve(),
  async (acc, (_, targetPath)) => {
    let _ = await acc
    // ... PathSecurity.isWithinTree, backupIfOverwriting, fs.mkdir, fs.cp ...
  },
)
```

`rollbackOutput` (lines 131-150):
```rescript
let _ = await committedFiles->Array.reduce(Promise.resolve(), (acc, outputPath) => {
  acc->Promise.then(async _ => {
    // ... fs.cp backup or fs.rm newly created ...
  })
})
```

Both chains use `errorRef` (commitFiles) or `failedPaths` (rollback) for
error collection — they accumulate results into mutable refs.

**Convention**: ReScript Async/await syntax. Promise chaining via `->Promise.then`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**: `src/application/pipeline/Commit.res`

**Out of scope**:
- Phase2.res (uses re-exported aliases; no change needed if types stay)
- Any port interface changes
- Any test changes (existing tests should pass unchanged)

## Steps

### Step 1: Parallelize commitFiles

Replace the `Array.reduce` sequential chain with `Array.map` + `Promise.all`.

The current pattern:
```rescript
let _ = await renderedFiles->Array.reduce(
  Promise.resolve(),
  async (acc, (_, targetPath)) => {
    let _ = await acc
    // ... work ...
  },
)
```

New pattern:
```rescript
let results = await renderedFiles->Array.map(((_, targetPath)) => {
  // isolate the work in an async function
  let work = async () => {
    let stagedPath = path.join(stagingDir, targetPath)
    let destPath = path.join(outputDir, targetPath)
    let destDir = path.dirname(destPath)
    let isWithin = await PathSecurity.isWithinTree(destPath, outputDir, path, fs)
    if !isWithin {
      Error("Target path outside output tree: " ++ targetPath)
    } else {
      switch await backupIfOverwriting(~targetPath, ~outputDir, ~stagingDir, ~fs, ~path) {
      | Error(e) => Error(e)
      | Ok(backupOpt) => {
          backupOpt->Option.forEach(entry => {
            let _ = backups->Array.push(entry)
          })
          try {
            let _ = await fs.mkdir(destDir, ~options={recursive: true})
            await fs.cp(stagedPath, destPath, ~options={recursive: false})
            let _ = partialCommit->Array.push(destPath)
            Ok()
          } catch {
          | JsExn(obj) => Error(...)
          }
        }
      }
    }
  }
  work()
})
```

CRITICAL: The `backupIfOverwriting` check uses `fileExists` on the target
path. When parallelized, two files targeting the same output path create
a race — both check `fileExists`, both see `false`, then both try to write.
**Mitigation**: Before the parallel map, deduplicate target paths. Keep the
first occurrence, warn on duplicates. Add:

```rescript
let seenTargets = Set.String.make()
let dedupedFiles = renderedFiles->Array.filter(((_, targetPath)) => {
  if Set.String.has(seenTargets, targetPath) {
    Console.warn("Duplicate target path: " ++ targetPath ++ " — skipping")
    false
  } else {
    Set.String.add(seenTargets, targetPath)
    true
  }
})
```

### Step 2: Collect results after Promise.all

After `Promise.all`:
```rescript
let errors = results->Array.keepMap(r => switch r { | Error(e) => Some(e) | Ok() => None })
if errors->Array.length > 0 {
  // short-circuit: report first error
  let firstError = errors[0]->Option.getOr("Unknown error")
  let err: phase2Error = {message: firstError}
  switch partialCommit->Array.length {
  | 0 => Error(err)
  | _ => Error({...err, partialCommit: Some(partialCommit)})
  }
} else {
  Ok((Array.length(partialCommit), backups))
}
```

### Step 3: Parallelize rollbackOutput

Replace the `Array.reduce` chain with `Promise.all`:

```rescript
let results = await committedFiles->Array.map(outputPath => {
  let work = async () => {
    switch backups->Array.find(b => b.outputPath == outputPath) {
    | Some(backup) => {
        try {
          await fs.cp(backup.backupPath, outputPath, ~options={recursive: false})
          Ok()
        } catch {
        | _ => Error(outputPath)
        }
      }
    | None => {
        try {
          await fs.rm(outputPath, ~options={recursive: false})
          Ok()
        } catch {
        | _ => Error(outputPath)
        }
      }
    }
  }
  work()
})
```

Then collect errors:
```rescript
let failedPaths = results->Array.keepMap(r => switch r { | Error(p) => Some(p) | Ok() => None })
switch failedPaths->Array.length {
| 0 => Ok()
| _ => Error(failedPaths)
}
```

### Step 4: Build and test

```bash
pnpm res:build
pnpm res:test
```

All Phase2 commit/rollback tests must pass. Special attention to the
`makeFsWithFailures` injection pattern in Phase2_test that injects cp/rm
failures — those should still trigger rollback correctly with parallel code.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 — all commit/rollback tests pass
- [ ] `grep -n "Array.reduce.*Promise" src/application/pipeline/Commit.res` returns 0 (no more sequential chains)
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code at the locations doesn't match the excerpts.
- A step's verification fails twice after a reasonable fix attempt.
- The rollback tests fail — rollback correctness is non-negotiable.
- The deduplication check reveals existing tests that rely on duplicate
  target paths (report the finding — it's a template-authoring bug).

## Maintenance notes

The parallel commit changes the error-semantics slightly: instead of
short-circuiting on first error (the old sequential reduce pattern),
parallel execution collects all errors and reports the first one.
This means more files may be committed before an error is detected,
but rollback still cleans up correctly.

If a template creates two files targeting the same path (a template error),
the deduplication step silently skips the second. The old code would
also overwrite (the second commit would overwrite the first). The new
behavior is actually safer — but log it so template authors can debug.
