# Plan 052: Parse documented timeout duration strings (and reject garbage loudly)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/infrastructure/config/ConfigJsonParser.res src/infrastructure/config/ConfigLogic.res src/infrastructure/hooks/Hooks.res src/interfaces/cli/commands/Init.res test/Config_test.res test/ConfigJsonParser_test.res README.md docs/api-reference.md docs/setup.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (widens accepted input to what the docs already promise)
- **Depends on**: none (ledger residual #5 adjacent — see Maintenance notes)
- **Category**: bug
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

The scaffolded config and three docs tell users to write hook timeouts as
duration strings (`timeout: 5s`, `"30s"`, `"5m"`). The parser reads the field
ONLY as a JSON number; any other shape silently becomes `None`, which falls
back to the 5-second default. A user who writes `timeout: 30s` to lengthen
a slow hook gets it KILLED EARLY with zero diagnostics — the exact opposite
of their intent, invisibly. Meanwhile genuinely invalid values (booleans,
garbage strings, non-finite numbers) also pass silently. Accept what the
docs promise; reject everything else loudly.

## Current state

At `100b121`:

- `src/infrastructure/config/ConfigJsonParser.res:126-130` — the hooks
  `timeout` field: `switch json { | JSON.Number(n) => Some(...) | _ => None }`
  (verify the exact shape; the key fact: non-Number → `None` silently).
- `src/interfaces/cli/commands/Init.res:6` — the scaffolded project config
  writes `timeout: 5s` (a STRING — immediately ignored by the parser above).
- Docs promising strings: `README.md:301`,
  `docs/api-reference.md:156` (`"30s","5m"` examples),
  `docs/setup.md:37`.
- `src/infrastructure/config/ConfigLogic.res:42-43` — validation:
  `timeout < 1` rejection (verify exact comparator). NaN fails `< 1`
  comparisons (NaN < 1 is false), so a NaN could slip through — guard at
  parse.
- `src/infrastructure/hooks/Hooks.res:172-177` — use-site clamp: values
  above 600s clamp; `timeout: 0` is blocked on the CLI generate path
  (`src/interfaces/cli/commands/Generate.res:23`) but unvalidated for
  direct `Engine.run` callers (ledger residual #5 — do not relitigate the
  clamp here; just make parsing total).
- `test/Config_test.res:30` — the existing timeout test covers numbers
  only; no string-duration test exists.
- Ledger: `odd/tasks/production-readiness-hardening.md` residual #5
  (`hooks.timeout <= 0`) — this plan closes the STRING-contract half; the
  lower-bound/NaN hardening below also tightens the rest.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/Config_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/config/ConfigJsonParser.res`
- `src/infrastructure/config/ConfigLogic.res` (only the NaN/lower-bound guard)
- `test/Config_test.res` (and `test/ConfigJsonParser_test.res` if that is
  where parser cases live — check both)

**Out of scope** (do NOT touch):
- `Init.res` scaffold content (`timeout: 5s` becomes VALID once parsing
  accepts strings — keep it).
- The docs (they already document the string contract; the code catches up).
- `Hooks.res` 600s clamp semantics (ledger residual; unchanged).
- Global-config error surfacing (match whatever channel
  `ConfigJsonParser`/`ConfigStore` already uses — see Step 1).

## Git workflow

- Branch: `fix/052-timeout-duration-strings`
- Conventional commits, e.g. `fix(config): parse documented timeout duration strings and reject invalid values`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Pin the error channel (READ-ONLY)

Read `ConfigJsonParser.res` around the hooks parsing to see how OTHER
invalid fields are handled today (silent `None` vs a collected validation
error vs a thrown parse error — `ConfigStore.res:94`'s global warn path is
the adjacent precedent). The new rejections must ride the SAME channel the
module already uses for invalid fields; do not invent a new one.

**Verify**: your notes name the channel; no code changed.

### Step 2: Parse duration strings and validate numbers

In the hooks `timeout` field parsing:

1. `JSON.Number(n)`: accept only finite integers `n >= 1` (reject
   non-integers, non-finite — `.nan`/`.inf` YAML — with the Step 1 channel;
   reject `n < 1` the same way rather than silently defaulting).
2. `JSON.String(s)`: accept `^([0-9]+)(s|m)$` → seconds (`"30s"` → 30,
   `"5m"` → 300); apply the same `>= 1` bound (`"0s"` → reject). Bare
   digits (`"30"`) → REJECT with a message telling the user to add a unit
   (ambiguous input should not guess).
3. Anything else (`true`, objects, garbage strings) → reject via the Step 1
   channel with a message naming the field and the found shape.

Match `ConfigLogic.res`'s existing validation message style verbatim
(`timeout must be >= 1` — read it first).

**Verify**: `pnpm res:build` → exit 0.

### Step 3: Guard the validator against NaN

In `ConfigLogic.res`, change the lower-bound check from `timeout < 1` to
`!(timeout >= 1)` (NaN fails `>= 1`, so `!(...)` catches it) — or add an
explicit finite/integer check if the module has an established pattern.
Message unchanged in wording.

**Verify**: `pnpm res:build` → exit 0.

### Step 4: RED→GREEN tests

In `test/Config_test.res` (and/or the parser test file where timeout cases
live — model after the existing `:30` numeric case):

1. `"30s"` → timeout 30 (RED today: silently None).
2. `"5m"` → timeout 300 (RED today).
3. `30` (number) → 30 (regression).
4. `"0s"`, `"0"` , `-5` (number) → validation rejection naming the field
   (RED today for the string forms; `-5` may already reject — assert
   whichever is the POST-change contract).
5. `"30"` (bare digits, no unit) → rejection telling the user to add a unit.
6. `true` / `"abc"` / `1.5` / `.nan` → rejection (RED today: silent None).

**Verify**: `npx retest ./test/Config_test.res.mjs` → all pass; `pnpm res:test` → all pass (update only tests that enshrined silent-None with `// plan 052` comments).

## Test plan

- The 6 cases above.
- Full-suite gate; `test/HookSecurity_test.res:565` (600s clamp) must keep
  passing unchanged.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the new duration-string cases
- [ ] `"30s"` parses to 30 and `"0s"` rejects (both test-asserted)
- [ ] The scaffolded `timeout: 5s` from `Init.res` now round-trips as a valid 5-second timeout (integration-level assert if a config-load test exists)
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The module's established error channel cannot carry field-level
  rejections (then surface the design question — do not throw ad hoc).
- Existing tests ENSHRINE silent-None for garbage timeouts as intentional
  (surface the contract question instead of silently rewriting them).
- YAML `.nan` cannot reach the parser as a `JSON.Number` in this stack
  (then the NaN guard is untestable — report and keep it as belt-and-braces
  with a comment).

## Maintenance notes

- Ledger residual #5 (`hooks.timeout <= 0` via unvalidated `Engine.run`
  callers): Step 3's validator tightening narrows it further; the remaining
  half (validate at the `Hooks.run` boundary for direct callers) stays in
  the ledger.
- If hours (`"1h"`) are ever requested, extend the regex — do not add
  free-form parsing.
- Docs stay as-is: they already document the string contract this plan
  implements.
