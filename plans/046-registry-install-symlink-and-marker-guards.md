# Plan 046: Refuse registry installs that ship symlinks or forged markers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/interfaces/cli/TemplateRegistry.res src/interfaces/cli/TemplateRegistry.resi src/interfaces/cli/commands/TemplateCopy.res test/TemplateRegistry_test.res`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (adds an install-time refusal; clean installs unchanged)
- **Depends on**: none (038 landed — this hardens its install path)
- **Category**: security
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

Registry install copies a user-supplied source directory with `fs.cp`, whose
default PRESERVES symlinks, and then writes the `.blueprint-provenance`
marker with `writeFile`. If the source ships `.blueprint-provenance` as a
symlink, the copied marker is still a symlink and `writeFile` follows it —
the marker text ("source: ...\ninstalled_at: ...") is written THROUGH it
into an attacker-chosen user-owned file (install-time clobber). Planted
symlinked `.ejs.t` files also persist in the registry. Registry-installed
templates are the UNTRUSTED tier (that is the entire point of plan 038's
provenance gate), so install must refuse sources containing symlinks or a
pre-existing marker instead of copying them faithfully.

Framing note (do not overstate): installation already requires an explicit
default-NO confirmation naming the source path, so this is defense-in-depth
against a supplied-directory clobber, not a demonstrated privilege
escalation.

## Current state

At `100b121` (`src/interfaces/cli/TemplateRegistry.res`):

- `:27-58` — overwrite branch: user confirms → `rm(targetPath, recursive)` →
  `mkdir(registryRoot, recursive)` → `cp(sourceAbs, targetPath, ~options={recursive: true})`
  (at `:38-40`) → `writeFile(markerPath, "source: ...", ...)` (at `:42-45`).
- `:59-71` — fresh branch: same `rm`-skip → `mkdir` → `cp` (`:61-64`) →
  `writeFile(markerPath, ...)` (`:65-69`).
- `markerPath = deps.path.join(targetPath, ".blueprint-provenance")`.
- The fs port's `cp` options expose no `dereference` flag
  (`src/infrastructure/bindings/NodeJs/Fs.res:15` — cpOptions) — Node's
  `fs.cp` default `dereference: false` stands.
- No validation of the source tree happens before the copy: no symlink
  scan, no marker-existence check.
- `src/interfaces/cli/commands/TemplateCopy.res:27-33` — the CLI asks the
  install confirmation (default NO) before reaching this code.
- `test/TemplateRegistry_test.res` — existing install tests use injected
  fake fs/path ports and record operations; model new tests on them.
- `Ports.fileSystem` has `lstat` (used by `Commit.res:46`), `readdir`
  (`Discovery.res:152`, options `{withFileTypes: false}` — string names),
  `stat`, `fileExists` — everything a recursive walk needs.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/TemplateRegistry_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/interfaces/cli/TemplateRegistry.res`
- `test/TemplateRegistry_test.res`

**Out of scope** (do NOT touch):
- `Ports.res` / bindings `cp` options — do NOT add a `dereference` flag;
  refusing symlinks is stricter and simpler than dereferencing them.
- `TemplateCopy.res` confirmation flow — unchanged.
- Generate-time symlink defenses (`Commit.res:46,113`, staging checks) —
  they stay as the second layer; this plan is the install-time first layer.
- The provenance/EJS trust-model question — plan 050 owns that decision.

## Git workflow

- Branch: `fix/046-registry-install-symlink-guards`
- Conventional commits, e.g. `fix(registry): refuse installs shipping symlinks or provenance markers`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Implement the source-tree validation

Add a local async helper in `TemplateRegistry.res` (match the file's
existing helper style):

`validateSourceForInstall: (~source: string, ~fs: Ports.fileSystem, ~path: Ports.path) => promise<result<unit, string>>`

Recursive walk (`readdir` for names + `lstat` each entry + `stat`
`source` itself first):

1. If any entry (or the source root) `isSymbolicLink()` → return
   `Error("Refusing to install <source>: symbolic links are not allowed in templates")`.
2. If the source root contains a `.blueprint-provenance` file → return
   `Error("Refusing to install <source>: source already contains a .blueprint-provenance marker")`
   (a source shipping its own marker is forging provenance).
3. Directories recurse; regular files pass. Bound the walk defensively with
   a depth cap (e.g. 32) and an entry cap (e.g. 10,000) → `Error` naming
   the cap on breach (a supplied tree should not be able to hang the walk).

Call it at the TOP of BOTH install branches (`:27-58` and `:59-71`), BEFORE
any `rm`/`mkdir`/`cp` — a refused install must leave the registry and the
target completely untouched.

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Post-copy marker sanity check (defense in depth)

After `cp` and before `writeFile(markerPath, ...)`: `lstat(markerPath)` —
if it exists at all (it should never — Step 1 refused sources containing
it), or is a symlink, remove `targetPath` recursively and return the same
forged-marker error. This guards against a cp semantics change ever
reintroducing the write-through.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/TemplateRegistry_test.res.mjs` →
existing install tests still pass (clean sources unaffected).

### Step 3: RED→GREEN tests

In `test/TemplateRegistry_test.res` (fake fs ports record all ops), model
on the existing install/overwrite tests:

1. Source whose `.blueprint-provenance` is a SYMLINK → `Error` with the
   marker message; fake fs recorded ZERO `cp`/`writeFile`/`rm` on the
   registry target; no `writeFile` to ANY path outside expectations
   (RED today: install proceeds and writeFile goes through the symlinked
   marker).
2. Source containing any other symlink (e.g. `templates/x.ejs.t` → link) →
   `Error` with the symlink message; registry untouched.
3. Source exceeding a cap (depth or entries) → `Error` naming the cap.
4. Clean source → install succeeds, marker written as a regular file,
   provenance content unchanged (regression guard for 038's behavior).
5. Overwrite branch with a pre-existing valid registry entry + clean new
   source → still works after re-validation (regression guard).

Write cases 1-2 first and confirm RED against current behavior.

**Verify**: `npx retest ./test/TemplateRegistry_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The 5 cases above in `test/TemplateRegistry_test.res`.
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new refusal tests
- [ ] A symlinked-marker source install returns `Error` and performs zero registry mutations (test-asserted)
- [ ] Clean-source install tests from plan 038 still pass unchanged
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- `Ports.fileSystem` lacks a capability the walk needs (e.g. no `lstat` on
  the port — it exists at `Commit.res:46`'s usage, but verify the `.resi`).
- Existing 038 install tests assert that symlinked sources INSTALL
  successfully (would be an intentional contract — surface it).
- The recursive walk cannot reuse the fake-fs patterns the existing tests
  use (mock fidelity gap — report rather than weakening tests).

## Maintenance notes

- Reviewer focus: validation must run BEFORE the overwrite `rm` — a refused
  overwrite must not delete the existing registry entry.
- If `fs.cp` options ever gain a `dereference` binding, keep the refusal
  anyway (dereferencing a symlinked tree copies attacker-controlled
  content; refusal is the safer default for the untrusted tier).
- Related follow-up (deferred): `template remove` deletes a config-supplied
  `entry.path` with no containment check (`TemplateRegistry.res:105-108`)
  — flagged as local defense-in-depth in the 2026-10-01 audit; plan
  separately if the registry root gains an invariant worth enforcing.
