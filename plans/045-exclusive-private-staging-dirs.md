# Plan 045: Create staging directories exclusively and privately

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/infrastructure/adapters/NodeJsFileSystem.res src/infrastructure/adapters/NodeJsFileSystem.resi src/domain/ports/Ports.res src/infrastructure/bindings/NodeJs/Fs.res src/infrastructure/bindings/NodeJs/Os.res src/application/pipeline/Staging.res src/application/engine/EngineLifecycle.res test/Staging_test.res test/Engine_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (adapter-local change; port signature unchanged)
- **Depends on**: none (coordinate with 044 — same lifecycle area)
- **Category**: security
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

The staging directory holds rendered output AND backups of the user's
existing files (`Commit.res:34-48` copies overwrite-targets into it). Today
it is created with a timestamp + `Math.random` name via a recursive `mkdir`
with no mode: not exclusive (a pre-created predicted name is accepted), not
explicitly private (permissions default to umask, typically 0755 on shared
hosts), and on failure the adapter returns the path anyway (fail-open —
masked for the main caller by `Staging.create`'s re-mkdir, but still wrong).
On multi-user machines other local users can read the user's backed-up file
contents. Node's native `fs.mkdtemp` fixes all three at once: exclusive
creation, `0700` permissions, and a genuinely random suffix.

Framing note (do not overstate): the fail-open branch is masked by
`Staging.create`'s fail-closed re-mkdir for the generate path; the material
wins here are exclusivity and privacy.

## Current state

At `100b121`:

- `src/infrastructure/adapters/NodeJsFileSystem.res:80-92` —

```rescript
makeStagingDir: async _prefix => {
  let ts = Date.now()->Float.toInt->Int.toString
  let r = Math.random()->Float.toString
  let r2 = String.split(r, ".")->Array.get(1)->Option.getOr("x")
  let dir = "blueprint-" ++ ts ++ "-" ++ r2
  let tmp = NodeJs.Os.tmpdir()
  let fullPath = NodeJs.Path.join(tmp, dir)
  try {
    let _ = await NodeJs.Fs.mkdir(fullPath, ~options={recursive: true})
    fullPath
  } catch {
  | _ => fullPath    // ← fail-open: returns the path even if mkdir failed
  }
}
```

  Note the `_prefix` parameter is IGNORED (underscore-prefixed).
- `src/domain/ports/Ports.res` — `Ports.fileSystem` type declares
  `makeStagingDir` (keep its signature `string => promise<string>`; check the
  exact declaration and keep it — this plan changes only the
  implementation).
- `src/application/pipeline/Staging.res:7-19` — `create(~tmpDir, ~fs)`:
  `mkdir(tmpDir, recursive)` and `Error(msg)` on failure. With mkdtemp this
  re-mkdir is a harmless no-op on an existing own dir — leave it unchanged.
- `src/application/engine/EngineLifecycle.res:15-27` —
  `parseStagingDirTimestamp` parses `blueprint-<ts>-<rest>` names
  (`parts[1]` = timestamp; a `-`-prefixed ts handled via `parts[2]`).
  `:38-40` — `cleanupOrphans` probes the tmp root via
  `fs.makeStagingDir(stagingDirPrefix ++ "tmp-root-probe")` and removes the
  probe immediately.
- `src/infrastructure/bindings/NodeJs/Os.res:11-22` — a DUPLICATE sync
  `makeStagingDir` (same `Math.random` + recursive mkdir + fail-open).
  Grep its callers in Step 1.
- `src/infrastructure/bindings/NodeJs/Fs.res` — the fs binding module; add
  the `mkdtemp` external here (follow the existing `@module("node:fs")` /
  fs-promises binding style used by `mkdir`, `cp`, `writeFile` — read the
  file first and match it exactly, including whether async ops bind via
  `@module("node:fs/promises")`).

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Staging_test.res.mjs ./test/Engine_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/bindings/NodeJs/Fs.res` (+ `.resi` if it has one)
- `src/infrastructure/adapters/NodeJsFileSystem.res`
- `src/infrastructure/bindings/NodeJs/Os.res` (delete the duplicate only if
  Step 1 proves it unused)
- `test/Staging_test.res`, `test/Engine_test.res` (and a new adapter test
  file if cleaner)

**Out of scope** (do NOT touch):
- `Ports.res` type signature — unchanged.
- `Staging.res`, `Commit.res`, `Phase2.res` — no changes needed.
- `EngineLifecycle.res` thresholds/parse logic — the new name format MUST
  stay compatible with `parseStagingDirTimestamp` (verified in Step 3).

## Git workflow

- Branch: `fix/045-private-exclusive-staging`
- Conventional commits, e.g. `fix(staging): create staging dirs with mkdtemp (exclusive, 0700)`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Pin the duplicate's callers (READ-ONLY)

`grep -rn "Os.makeStagingDir\|makeStagingDir" src/ test/` — list every
caller of BOTH implementations. Expected: `EngineLifecycle` (probe) and
`NodeJsFileSystem` adapter (the port impl). If `NodeJs/Os.res`'s version has
live callers, STOP and report (aligning it is a scope decision); if unused,
delete it in Step 4.

**Verify**: caller list recorded; no code changed.

### Step 2: Implement `mkdtemp` in the adapter

1. In `src/infrastructure/bindings/NodeJs/Fs.res`, add an async `mkdtemp`
   external matching the module's existing binding style for async
   operations (`path => promise<string>`).
2. Rewrite `NodeJsFileSystem.makeStagingDir` to honor the prefix:

```rescript
makeStagingDir: async prefix => {
  let fullPath = await NodeJs.Fs.mkdtemp(NodeJs.Path.join(NodeJs.Os.tmpdir(), prefix))
  fullPath
}
```

   No try/catch: a creation failure must reject (fail closed), not return a
   phantom path. Name compatibility: callers pass `"blueprint-"`-style
   prefixes — check every caller's prefix string (`EngineLifecycle` probe
   passes `stagingDirPrefix ++ "tmp-root-probe"`; find the generate-path
   caller and confirm its prefix ENDS the timestamp segment, e.g.
   `"blueprint-" ++ ts ++ "-"`, so `parts[1]` still parses; if a caller
   passes a prefix that would break `parseStagingDirTimestamp`, adjust that
   caller's prefix string in the same commit).

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → failures only in
tests that asserted the old name format or the fail-open behavior (fix them
in Step 3; list every updated test).

### Step 3: Compatibility + privacy tests

1. If no adapter-level test file exists for `makeStagingDir`, add the cases
   to `test/Staging_test.res` (or a new `test/NodeJsFileSystem_test.res`
   following its conventions):
   - Returned path exists, is a directory, and its name starts with the
     passed prefix.
   - Two consecutive calls return DIFFERENT paths (mkdtemp randomness).
   - `stat` mode check: `(stat.mode & 0o777) == 0o700` (POSIX only — guard
     with `Sys.os_type` or skip the mode assert on Windows; check how
     existing tests handle platform differences, if at all).
   - The generate-path caller's produced name still round-trips through
     `EngineLifecycle.parseStagingDirTimestamp` (import it; assert `Some(_)`)
     so the orphan sweep keeps finding these dirs.
2. `test/Engine_test.res`: the orphan-sweep tests keep passing (name format
   compatible). If a sweep test constructs old-format names manually, update
   the fixture to the new format with a `// plan 045` comment.

**Verify**: `npx retest ./test/Staging_test.res.mjs ./test/Engine_test.res.mjs` → all pass; `pnpm res:test` → all pass.

### Step 4: Remove the dead duplicate

If Step 1 proved `NodeJs/Os.res:11-22` unused: delete `makeStagingDir`
there (commit separately: `chore(bindings): drop duplicated makeStagingDir`).

**Verify**: `pnpm res:build` → exit 0; `grep -rn "makeStagingDir" src/infrastructure/bindings/NodeJs/Os.res` → no matches.

## Test plan

- Cases from Step 3; model file/fixture style after `test/Staging_test.res`.
- Full-suite gate (many suites create staging dirs via the port — the
  format change must not break them).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new exclusivity/privacy/mode tests
- [ ] `grep -n "Math.random" src/infrastructure/adapters/NodeJsFileSystem.res src/infrastructure/bindings/NodeJs/Os.res` returns no matches
- [ ] `parseStagingDirTimestamp` round-trip test passes (orphan sweep compatibility)
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Any caller's prefix cannot be made timestamp-compatible with
  `parseStagingDirTimestamp` without changing that caller's semantics.
- `NodeJs/Os.res`'s duplicate has live callers.
- The fs binding module's style cannot express an async `mkdtemp` external
  cleanly (surface the binding question instead of inventing `%raw` unless
  `%raw` is already the module's established pattern for such calls).
- More than ~5 test suites break on the name-format change beyond fixture
  updates (indicates hidden coupling to the old format).

## Maintenance notes

- `Staging.create`'s re-mkdir is now redundant (mkdtemp already created the
  dir); it is left in place deliberately — removing it is a separate
  hygiene commit if desired.
- Ledger alignment: this closes the "predictable/fail-open staging" residual
  (#9 in `odd/tasks/production-readiness-hardening.md`) beyond the
  previously-known masking nuance; note that in the ledger when updating it.
- Cross-platform note: `0700` is POSIX; Windows mkdtemp permissions differ —
  the mode test must be POSIX-guarded.
