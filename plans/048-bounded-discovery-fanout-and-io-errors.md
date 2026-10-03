# Plan 048: Bound discovery concurrency and surface I/O failures

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat <047-landing-SHA>..HEAD -- src/infrastructure/discovery/Discovery.res src/infrastructure/discovery/Discovery.resi test/Discovery_test.res`
> Plan 047 must be DONE before starting this plan (it restructures the same
> module). Use the SHA recorded in `plans/README.md`'s 047 row. If 047 is not
> DONE, STOP. If any in-scope file changed since 047 landed, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (bounded pool + warnings; result order and skip semantics preserved)
- **Depends on**: plan 047 (same-module restructure)
- **Category**: perf
- **Planned at**: commit `100b121`, 2026-10-01 (against the pre-047 shape; line references are to the 047 shape)

## Why this matters

Discovery fans out one promise per template file (and per directory read)
with NO concurrency bound — a large registry produces an unbounded I/O burst
(hundreds of simultaneous opens). Worse, non-parse I/O errors are swallowed
(`catch { | _ => None }` / `catch { | JsExn(_) => [] }`): a generator that
fails to read because of `EMFILE`/`EACCES` silently vanishes, and the user
sees "generator not found" — a misleading diagnosis with no diagnostic.
Bounded concurrency plus ENOENT-vs-real-error classification fixes both.

## Current state

At `100b121` (pre-047; adjust to the post-047 shape when executing):

- `src/infrastructure/discovery/Discovery.res:44-61` (`_loadTemplate`) — the
  catch arm returns `None` for ANY non-parse error (only
  `"Parse error in "` messages warn). An `EMFILE`/`EACCES` read failure
  makes the template silently disappear.
- `src/infrastructure/discovery/Discovery.res:152-154,175-177,193-195` —
  `readdir` catches (`| JsExn(_) => []`) silently drop unreadable
  directories.
- `src/infrastructure/discovery/Discovery.res:177-184,210,244` — nested
  `Promise.all` over all files/dirs: unbounded concurrency.
- After plan 047: `loadGeneratorTemplates` holds the per-generator template
  fan-out; `discoverGenerators` the metadata walk — both inherit the same
  unbounded `Promise.all` + silent catches.
- `Console.warn` is the module's established diagnostic channel
  (`"Skipping generator ..."`, `"Skipping template ..."` at `:36-38`) —
  reuse it; tests already assert these texts.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Discovery_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/discovery/Discovery.res` (+ `.resi` if the pool helper is exported for tests)
- `test/Discovery_test.res`

**Out of scope** (do NOT touch):
- Warning texts for existing skip cases (byte-identical preservation).
- Result ORDER (search-path → generator → action → file order must hold).
- Any other module's `Promise.all` usage (Phase1/Commit parallel writes are
  already bounded by design — leave them).
- Retry/backoff — a warn is enough; do not add retries.

## Git workflow

- Branch: `perf/048-bounded-discovery-fanout`
- Conventional commits, e.g. `perf(discovery): bound template-loading concurrency and surface I/O failures`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: A small order-preserving bounded pool

Add a module-level helper (keep it private unless tests need it injected —
prefer designing tests around observable fs-port behavior instead):

```rescript
// Run async factories with at most `limit` in flight; results keep input order.
let maxConcurrent = 8
let mapBounded: (array<'a>, 'a => promise<'b>) => promise<array<'b>> = ...
```

Rolling-window implementation over a `ref<int>` cursor (or chunked batches
of `limit` — simpler and still order-preserving if you map results by
index; choose the simplest correct shape). Replace the template-loading
`Promise.all(filePromises)` fan-out with `mapBounded(files, loader)`.
Do NOT bound the manifest/metadata reads (small fan-out) unless trivial.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Discovery_test.res.mjs` → all pass (ordering preserved).

### Step 2: Classify I/O errors instead of swallowing

1. `_loadTemplate`'s catch: extract the error `code` where available (the
   fake-fs/real-error shape — check how other modules classify; e.g.
   `Errors.extractErrorMessage` at `src/infrastructure/bindings/Errors.res`
   and any existing code/classification precedent; if no code is
   accessible from the JsExn, use the message). Policy:
   - ENOENT / "no such file or directory" → silent `None` (expected race
     with a concurrently-deleted file — matches today's behavior).
   - anything else → `Console.warn("Skipping template " ++ path ++ ": " ++ msg)`
     and `None` (still skipped — discovery must not hard-fail on one bad
     file; but the user now sees WHY).
2. `readdir` catches: same split — ENOENT silent (expected: a search path
   without a `_templates` dir), other errors →
   `Console.warn("Skipping directory " ++ dirPath ++ ": " ++ msg)` + `[]`.

**Verify**: `pnpm res:build` → exit 0.

### Step 3: RED→GREEN tests

In `test/Discovery_test.res` (fake fs port; check how it throws errors —
record/extend the fake to raise with distinguishable messages such as
`"EACCES: permission denied"` / `"ENOENT: no such file"`):

1. One template read raises EACCES, others succeed → the EACCES template is
   absent BUT a warning naming it was emitted (capture `Console.warn` the
   way existing tests assert `"Skipping generator"` warnings); other
   templates discovered. (RED today: no warning.)
2. ENOENT on one template → still silent skip, no warning (preserved
   behavior).
3. `readdir` on an action dir raises EACCES → warning names the dir; the
   generator still contributes its other actions.
4. Concurrency bound: fake fs tracks peak in-flight `readFile` count (a
   counter incremented on call, decremented on resolve — add to the fake);
   fixture with 20 templates → assert peak ≤ 8. (RED against unbounded.)

**Verify**: `npx retest ./test/Discovery_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The 4 cases above in `test/Discovery_test.res`.
- Full-suite gate (warning-text assertions elsewhere must still pass — the
  new warnings are ADDITIVE; existing texts unchanged).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new warning + peak-concurrency tests
- [ ] A 20-template fixture's measured peak in-flight reads ≤ 8 (test-asserted)
- [ ] Existing `"Skipping generator"`/`"Skipping template"` warning texts are unchanged
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The fake fs port used by `Discovery_test.res` cannot represent error
  codes/messages (mock fidelity gap — extend the fake rather than weakening
  the classification, and report if the fake's shape is load-bearing
  elsewhere).
- Bounding the fan-out changes result ORDER anywhere (ordering is a hard
  contract — precedence and duplicate-name resolution depend on it).
- Plan 047 is not DONE (this plan's line references will not resolve).

## Maintenance notes

- `maxConcurrent = 8` is a judgment call, not a measurement — if a real
  registry ever justifies tuning it, make it config-driven then (not now).
- Reviewer focus: the pool must not swallow rejections (an unexpected
  exception in a loader must still propagate as today — only the
  classified catches change).
- If discovery ever gains a cache (none exists today — per-run `clearCache`
  in Fetcher is unrelated), revisit the ENOENT-silent policy.
