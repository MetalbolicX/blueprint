# Plan 060: Align documented directives with reality — drop `sh`, document `shell.enabled`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to
> the next step. If anything in the "STOP conditions" section occurs, stop
> and report — do not improvise. When done, update the status row for this
> plan in `plans/README.md` — unless a reviewer dispatched you and told
> they maintain the index.
>
> **Drift check (run first)**: `git diff --stat b2f2670..HEAD -- README.md AGENTS.md docs/api-reference.md docs/quick-reference.md src/infrastructure/config/ConfigJsonParser.res src/infrastructure/config/ConfigLogic.res`
> Semantic mismatch with the excerpts below is a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (docs only; no source behavior changes)
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `b2f2670`, 2026-10-05

## Why this matters

Two documented-contract lies:

1. The `sh:` template directive is documented in three living documents,
   but the parser rejects it by design — the shell-free posture landed by
   plans 035/039 made `sh` a hard error. Anyone writing a template
   against the README table hits `Unsupported directive: sh` at render
   time with no documented migration path.
2. `shell.enabled` is the gate for every tool/script execution and
   defaults to **false** (strict fail-closed — a config with a `shell:`
   section but no `enabled: true` silently disables shell features, and
   `enabled: true` without `tools` is a config error). None of this
   appears in README or the config reference; the only discoverability is
   the runtime error `Shell execution disabled`. Plan 039 recorded this
   docs gap as a known-open follow-up; it is still open (zero `enabled`
   mentions in README at the planned-at commit).

## Current state

**`sh` claims (to remove):**
- `README.md:190-197` — directives table; the offending row:
  `| \`sh\` | string | Shell command to execute after render |`
- `AGENTS.md:58` — "**Templates**: EJS `.ejs.t` files with YAML frontmatter (directives: `to`, `inject`, `after`, `before`, `prepend`, `append`, `force`, `sh`)"
- `docs/api-reference.md:80` — `| \`sh\` | string | shell | Command to execute after rendering |`
- Dated historical records that ALSO list `sh` —
  `docs/hygen-parity-handoff-2026-05-12.md:30`,
  `docs/blueprint-handoff-2026-05-11.md:22` — **do NOT edit these**
  (house precedent, plan 039 reconciliation: dated specs are records, not
  living docs).

**Code truth (do not change):**
- `src/domain/template/Frontmatter.res:105-107`:
  ```rescript
  } else if key == "sh" {
    Error("Unsupported directive: sh")
  } else {
  ```
- `test/Frontmatter_test.res:45-51` pins the rejection
  (`test("parse: sh directive is rejected", …)`).
- Accepted siblings immediately above: `tool`, `fetch` (HTTP-URL
  validated), `script`, plus `force`/`unless_exists` flags.

**`shell.enabled` truth (to document):**
- `src/infrastructure/config/ConfigJsonParser.res:234-260` —
  `parseShellConfig`: `let enabled = getBoolField(dict, "enabled", ~default=false)`
  and `Some({enabled, tools: ?tools, scripts: ?scripts, env: ?env})`.
- `src/infrastructure/config/ConfigLogic.res:46-47` —
  `| Some(s) if s.enabled && s.tools->Option.isNone => Error("shell.enabled=true requires tools to be defined")`.
- Enforcement + migration guide (plan 039 ruling): tool calls and script
  files hard-fail with `Shell execution disabled` unless
  `shell.enabled: true`; inline allowlisted commands run shell-free via
  `execFile` regardless.
- Existing docs that neighbor the gap: `README.md:294-306` (hooks
  section, `shell.tools` mention at `:306`), `README.md:399` (inline
  command behavior), `docs/api-reference.md:168` (`| \`shell\` | shell
  configuration | … |` — no subkeys), `docs/quick-reference.md:131`
  (effective project keys list — has `shell`, not `enabled`).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Claim gone (sh) | `grep -n '\`sh\`' README.md docs/api-reference.md` | no directive-table rows remain |
| Gap closed | `grep -cn "shell.enabled" README.md docs/api-reference.md docs/quick-reference.md` | ≥1 hit each |
| Whitespace | `git diff --check` | clean |

Docs-only change: ReScript build is unaffected (no need to run it; state
that in the report).

## Scope

**In scope**:
- `README.md`, `AGENTS.md`, `docs/api-reference.md`, `docs/quick-reference.md`

**Out of scope**:
- Any `.res`/`.resi` file; any dated handoff/spec record under `docs/`
  (filenames containing a date); the `force:` frontmatter gap (see
  Maintenance notes).

## Git workflow

- Branch: `docs/060-contract-sh-and-shell-enabled`
- Commit style: `docs: drop unsupported sh directive, document shell.enabled`
- Never commit on `main`; no push/PR unless instructed.

## Steps

### Step 1: Remove `sh` from living docs

- Delete the `sh` row from `README.md:190-197` table; add a one-line note
  under the table: `sh` is not supported (shell-free execution, plans
  035/039); use the `script:` directive (requires `shell.enabled: true`)
  or a lifecycle hook instead.
- `AGENTS.md:58`: drop `` `sh` `` from the directives list.
- `docs/api-reference.md:80`: remove the row; mirror the README migration
  note.

**Verify**: `grep -n '\`sh\`' README.md docs/api-reference.md` → no directive rows (the migration notes may mention `sh` in prose — that is intended).

### Step 2: Document `shell.enabled`

- In `README.md`, extend the configuration area around `:294-306` with a
  `shell:` block example and a short table for `enabled` / `tools` /
  `scripts` / `env`, stating: default `false`; strict fail-closed; the
  `Shell execution disabled` error is the migration guide; `enabled:
  true` requires `tools`; allowlisted inline commands run shell-free via
  `execFile` either way (consistent with `:306`/`:399`).
- `docs/api-reference.md:168`: expand the `shell` row into a subkey table
  matching `ConfigJsonParser`'s four fields and the `ConfigLogic` rule.
- `docs/quick-reference.md:131`: add `shell.enabled` to the effective
  project keys list.

**Verify**: `grep -n "shell.enabled" README.md docs/api-reference.md docs/quick-reference.md` → ≥1 hit each; read the rendered sections once for factual accuracy against the excerpts above.

### Step 3: Final checks

**Verify**: `git diff --check` → clean; `git status` → only the four in-scope files touched.

## Test plan

- Docs-only: verification is the grep table above plus a factual re-read
  of each new section against the quoted source truth. No test changes.

## Done criteria

- [ ] `sh` directive rows gone from README/api-reference; AGENTS.md list fixed
- [ ] `shell.enabled` documented in all three living docs, consistent with parser/validation excerpts
- [ ] Dated handoff records untouched
- [ ] Only in-scope files modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Any fact you cannot verify against the quoted source excerpts (do not
  guess config semantics).
- You find another living doc (non-dated) documenting `sh` as supported —
  add it to scope only if trivially the same edit; otherwise report it.

## Maintenance notes

- Sibling gap, deliberately not solved here (needs a maintainer design
  decision): `force:` frontmatter is parsed but never consumed, while
  `docs/quick-reference.md:44` promises it — recorded in
  `plans/README.md`'s known-open list. Fixing it means either consuming
  `force` or de-documenting it; do not silently do either in a docs pass.
- Reviewer focus: the `shell.enabled` table must not weaken the
  fail-closed story (default false is a feature).
