# Plan 009: Wire `dry_run` config field into the pipeline

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/application/engine/Engine.res src/application/pipeline/Phase1.res src/infrastructure/config/ConfigYaml.res src/domain/config/ConfigTypes.res src/interfaces/cli/Commands.res`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: direction
- **Planned at**: commit `3a6df55`, 2026-06-29

## Design decision

**What does dry run do?**
- Skip Phase2 entirely (no files written to output)
- Print a message like `"Dry run — would generate N file(s)"`
- Exit 0

No shell commands are executed, no files are written, no rollback is needed.
The staging directory is created and cleaned up as normal.

## Why this matters

The `dryRun` field is fully parsed from YAML, serialized back, tested for
roundtrip — but never consumed. A user setting `dry_run: true` in config
gets identical behavior to `dry_run: false`. This is the highest-leverage
unfinished-intent finding: half the implementation exists (config path),
and the fix is a single conditional branch in the orchestrator.

## Current state

**ConfigTypes.res** (lines 57, 67, 76): `dryRun: bool` exists in both
`globalConfig` and `mergedConfig`, defaults to `false`.

**ConfigYaml.res** (lines 32, 369-396, 439): Parses `dry_run` from YAML,
serializes it to YAML, and merges it. Fully tested.

**Engine.res** (lines 209-350): The `run` function's `~config` parameter
is an `option<Config.config>`. There is no `dryRun` check anywhere.

**Pipeline**: Phase1 renders to staging, Phase2 commits to output.
The boundary between Phase1 and Phase2 is the natural insertion point.

**Note**: `Engine.run` receives a `Config.config` not `Config.mergedConfig`.
The `dryRun` field lives on `globalConfig`/`mergedConfig` but not on `config`.
This means we need to either:
- (a) Add `dryRun` to `config` type, or
- (b) Pass a separate `dryRun` parameter, or
- (c) Thread `mergedConfig` through `Engine.run`.

Option (a) is cleanest: add `dryRun?: bool` to `ConfigTypes.config`.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |
| Bundle    | `pnpm bundle`            | exit 0              |

## Scope

**In scope**:
- `src/domain/config/ConfigTypes.res` — add `dryRun?: bool` to `config`
- `src/infrastructure/config/ConfigYaml.res` — parse/output new field
- `src/application/engine/Engine.res` — add dry-run check
- `src/interfaces/cli/Commands.res` — wire config to engine
- `test/Config_test.res` — add test for dry-run config parsing
- `test/Engine_test.res` — add test for dry-run skipping Phase2

**Out of scope**:
- Adding a `--dry-run` CLI flag (separate feature)
- Changing Phase1 or Phase2 internals
- Changing the shell execution path

## Steps

### Step 1: Add dryRun to config type

In `src/domain/config/ConfigTypes.res`, add to the `config` type (after line 41):
```rescript
  dryRun?: bool,
```

### Step 2: Update ConfigYaml to parse/output dryRun on config

In `src/infrastructure/config/ConfigYaml.res`, find the `parseConfig` function
that builds the `config` record. Add the dryRun field (model after how `output`
is parsed at lines 473-479):

```rescript
let dryRun = switch Dict.get(dict, "dry_run") {
| Some(v) =>
  switch v {
  | JSON.Boolean(b) => Some(b)
  | _ => None
  }
| None => None
}
```

And include it in the record: `dryRun: ?dryRun`.

Also update `serializeConfig` if one exists (check — it may only serialize
`globalConfig`).

### Step 3: Add dry-run check to Engine.run

In `src/application/engine/Engine.res`, after Phase1 succeeds and before
Phase2 runs (around line 305), add:

```rescript
// Dry run check: skip Phase2, report what would have been generated
let isDryRun = config->Option.flatMap(c => c.dryRun)->Option.getOr(false)
if isDryRun {
  stagingDirRef.contents = None
  proc.removeSignalListeners()
  Console.log("Dry run — would generate " ++ Int.toString(p1.renderedFiles->Array.length) ++ " file(s)")
  let _ = await Commit.rollback(p1.stagingDir, ~fs)
  let result: generateResult = {
    filesCreated: p1.renderedFiles->Array.length,
    filesInjected: 0,
    commandsExecuted: 0,
    classification: generator.name,
  }
  Ok(result)
} else {
  // existing Phase2 run
}
```

### Step 4: Ensure config passes through

In `src/interfaces/cli/Commands.res`, the `effectiveConfig` built for Engine.run
should include `dryRun` from `mergedConfig`:
```rescript
let effectiveConfig: Config.config = {
  output: ?projectConfig->Option.flatMap(c => c.output),
  dryRun: ?Some(mergedConfig.dryRun),
  ...
}
```

### Step 5: Add tests

In `test/Config_test.res`, add a test that parses a YAML snippet with 
`dry_run: true` and verifies the config has `dryRun: Some(true)`.

In `test/Engine_test.res`, add a test that Engine.run with `dryRun: true`
returns success but does not create files.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; new tests for dry-run exist and pass
- [ ] Setting `dry_run: true` in global config causes generation to skip Phase2
- [ ] Output shows a "Dry run" message with file count
- [ ] No files are created in the output directory during dry run
- [ ] Normal generation (without dry_run) is unaffected
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code doesn't match the excerpts (read the current files).
- A step's verification fails twice after a reasonable fix attempt.
- Normal generation output is affected by the dry-run changes.

## Maintenance notes

The `dryRun` field is on `config` (project config), not `mergedConfig`.
This means a project-level `.blueprint.yaml` can set it. Global config
`dry_run` would need to be pulled through separately if desired.
Add `--dry-run` CLI flag as a follow-up.
