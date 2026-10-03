# Plan 051: Treat backslash and drive-letter hook paths as paths

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/infrastructure/hooks/Hooks.res src/infrastructure/hooks/Hooks.resi src/domain/manifest/Manifest.res test/HookSecurity_test.res test/Manifest_test.res odd/tasks/production-readiness-hardening.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (classification tightening; slash-form behavior unchanged)
- **Depends on**: none (ledger residual #3's execution half)
- **Category**: security
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

Hooks classify a command as a PATH only when it contains `/`. Windows-style
path forms — `.\x.cmd`, `..\..\evil.cmd`, `C:\x.cmd` — contain no forward
slash, so they skip path resolution, containment, and existence checks and
run directly. On Windows they resolve relative-to-cwd or absolute,
bypassing the documented "restricted to the project tree" guarantee
(`README.md:306`). On POSIX they are merely literal filenames that fail
execution (no escape, but a confusing error). The manifest-side validator
has the same blind spot. This is ledger residual #3's input+execution
halves closing together.

## Current state

At `100b121`:

- `src/infrastructure/hooks/Hooks.res:10` — `_isPath = command ->
  String.includes(command, "/")` (verify the exact shape; it is a small
  local predicate used in the command-classification switch).
- `src/infrastructure/hooks/Hooks.res:74-97` — path-form commands: resolve
  against `scriptRoot`, containment-check via `isWithinTree`, existence-check;
  non-path commands skip all of that and run tokenized `execFile` (allowlist
  when configured, permissive when unset — documented behavior, do not
  change it).
- Slash-form containment WORKS: `../evil.sh` resolves against scriptRoot
  and is rejected when outside (`test/HookSecurity_test.res:72,132,600` —
  existing slash cases).
- `src/domain/manifest/Manifest.res:60-67` — `validateHookPath` rejects only
  `startsWith("/")` (an `includes("/")` check there is redundant) and checks
  `..` substring-wise; backslash/drive-letter forms pass manifest
  validation.
- `odd/tasks/production-readiness-hardening.md` residual #3 — the Windows
  backslash containment gap (read it; this plan closes its validation and
  classification halves; update the ledger row when done).
- `test/HookSecurity_test.res` — the hook test home (injected fake
  path/fs/shell ports); zero backslash cases today.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/HookSecurity_test.res.mjs ./test/Manifest_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/hooks/Hooks.res`
- `src/domain/manifest/Manifest.res`
- `test/HookSecurity_test.res`, `test/Manifest_test.res`
- `odd/tasks/production-readiness-hardening.md` (ledger row update only)

**Out of scope** (do NOT touch):
- Non-path hook commands' execution model (tokenized execFile + allowlist —
  plan 036's landed contract).
- `PathSecurity.res` — containment itself is separator-agnostic through the
  path port (`path.resolve`/`isWithinTree` via the injected port); only the
  CLASSIFICATION misses backslashes.
- Timeout clamping and env filtering — unrelated.

## Git workflow

- Branch: `fix/051-backslash-hook-paths`
- Conventional commits, e.g. `fix(hooks): classify backslash and drive-letter hook paths as paths`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Widen the path predicate

In `Hooks.res`, replace `_isPath` with a predicate that also matches:

- any `\` anywhere (`String.includes(command, "\\")` — in ReScript source a
  literal backslash string), AND
- a drive-letter prefix (uppercase or lowercase):
  `RegExp.fromString("^[A-Za-z]:")` + `RegExp.test`.

Keep `/` matching unchanged. Add a one-line comment:
`// Windows-style separators and drive roots are paths too (plan 051).`

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Reject Windows-absolute forms in `validateHookPath`

In `Manifest.res` `validateHookPath`: reject `startsWith("/")` (unchanged),
`startsWith("\\")` (backslash-absolute), and the drive-letter prefix
(`^[A-Za-z]:` — the same regex shape as Step 1, built once per the module's
existing style). Remove the redundant `includes("/")` if present. Keep the
`..` substring checks untouched.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Manifest_test.res.mjs` → all pass (slash rejections unchanged).

### Step 3: RED→GREEN tests

In `test/HookSecurity_test.res` (fake path/fs ports — the fake `path`
port's `resolve`/join must behave consistently; check how the existing
slash-containment tests drive it, and reuse that setup):

1. Hook command `.\local.cmd` (inside scriptRoot after resolution) → treated
   as a path: resolved + containment-checked + existence-checked; when the
   fake fs says it exists and is inside → executes via execFile on the
   resolved path (RED today: non-path tokenized run of a literal
   `.\local.cmd` filename).
2. Hook command `..\..\escape.cmd` (backslash traversal; fake fs places it
   OUTSIDE scriptRoot) → rejected with the containment error (RED today:
   runs uncontained).
3. Hook command `C:\absolute\x.cmd` → rejected (resolves absolute, outside
   scriptRoot; on the fake path port, an absolute input resolves to
   itself — assert the containment rejection).
4. Regression: `./scripts/pre.sh` inside scriptRoot → executes as today;
   `../outside.sh` → rejected as today (existing cases keep passing).

In `test/Manifest_test.res` (manifest validation cases):

5. `pre_generate: "C:\\x.cmd"` and `pre_generate: "\\x.cmd"` → manifest
   validation `Error` naming the field (RED today: accepted).
6. Regression: `"/abs.sh"` still rejected; `"./ok.sh"` still accepted.

**Verify**: `npx retest ./test/HookSecurity_test.res.mjs ./test/Manifest_test.res.mjs` → all pass; `pnpm res:test` → all pass.

### Step 4: Update the ledger

In `odd/tasks/production-readiness-hardening.md`, mark residual #3's
validation/classification halves closed by this plan (leave any
Windows-runtime-execution caveat that remains untested — no Windows
execution was performed by this plan; static classification only).

**Verify**: `grep -n "backslash" odd/tasks/production-readiness-hardening.md` shows the updated row.

## Test plan

- The 6 cases above across `test/HookSecurity_test.res` and
  `test/Manifest_test.res`.
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new backslash/drive-letter cases
- [ ] `grep -n "isPath" src/infrastructure/hooks/Hooks.res` shows the widened predicate (backslash + drive letter)
- [ ] `validateHookPath` rejects backslash-absolute and drive-letter forms (test-asserted)
- [ ] All existing slash-form hook tests pass unchanged
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Any legitimate hook command in the repo's own
  `_templates/`/`examples/` contains a backslash (grep them first:
  `grep -rn "pre_generate\|post_generate" _templates/ examples/` — if a
  real template ships a backslash non-path command, surface the conflict).
- The fake path port in tests cannot represent Windows-style resolution
  (extend the fake; if its shape is load-bearing for other suites, report).
- Containment via the ported `isWithinTree` turns out to be
  forward-slash-only internally (then the fix needs `PathSecurity` changes —
  out of scope; STOP and report).

## Maintenance notes

- No Windows execution was performed or tested by this plan — the
  classification change is static; a Windows CI runner would be the way to
  actually verify end-to-end (note that as a follow-up if Windows support
  becomes real).
- POSIX behavior note: backslash-containing non-path commands that USED to
  run (and fail with ENOENT-style errors) now take the path branch and fail
  earlier with clearer messages — that is the intended improvement, not a
  regression.
