# Plan 003: Fix stale documentation in README and quick-reference

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. When done, update the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- README.md docs/quick-reference.md`
> If these files changed since this plan was written, read the current versions
> and adjust line references before editing.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

Three categories of doc rot actively mislead users:
1. Wrong template file extension (`.ejs.ts` instead of `.ejs.t`) — users following
   the README create files the generator can't find.
2. References to `cwd`/`actionfolder` as template variables — these were stripped
   in WS4 for security (Context.res strips them at line 128-143).
3. `allow_dangerous_commands` config field — removed in WS4, but still documented.

Each of these causes real user confusion that a 1-line doc fix prevents.

## Current state

**File**: `README.md`
- Lines 28, 47: `Component.tsx.ejs.ts` — wrong extension, should be `Component.tsx.ejs.t`
- Lines 29, 48: Same extension pattern in example paths
- Line 248-249: Documents `cwd` and `actionfolder` in the Context variables table

**File**: `docs/quick-reference.md`
- Lines 53-54: Lists `cwd` and `actionfolder` in "Context keys"
- Line 134: `allow_dangerous_commands: true|false` — feature removed in WS4
- Line 136: `dry_run: true|false` — field is parsed but never consumed (see Plan 009)

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Verify    | `grep -rn "\.ejs\.ts" README.md docs/` | 0 matches |
| Verify    | `grep -rn "actionfolder" README.md docs/` | 0 matches (after removing from tables) |
| Verify    | `grep -rn "allow_dangerous" docs/` | 0 matches |

## Scope

**In scope**:
- `README.md`
- `docs/quick-reference.md`

**Out of scope**:
- `docs/api-reference.md` — separate issue
- `docs/setup.md` — separate issue
- `docs/architecture.md` — separate issue
- Any source code

## Steps

### Step 1: Fix template extension in README.md

Locate every occurrence of `.ejs.ts` in `README.md` and change to `.ejs.t`.

The pattern appears in the example directory tree and the template file example.
Search for `.ejs.ts` — there should be 4-6 occurrences. Replace each with
`.ejs.t`.

**Verify**: `grep -n "\.ejs\.ts" README.md` returns 0 matches.

### Step 2: Remove cwd/actionfolder from Context variables table

In `README.md`, find the table under "Context variables". Remove the two rows:
```
| `<%= cwd %>` | Current working directory |
| `<%= actionfolder %>` | Generator action folder path |
```

These are stripped from render context since WS4 (see Context.res:128-143).
The variables still exist internally for shell execution, but templates must
not access them.

**Verify**: `grep -n "cwd\|actionfolder" README.md` returns 0 matches.

### Step 3: Remove cwd/actionfolder from quick-reference context keys

In `docs/quick-reference.md`, locate the "Context keys" section (lines 50-61).
Remove the rows for `cwd` and `actionfolder`.

**Verify**: `grep -n "cwd\|actionfolder" docs/quick-reference.md` returns 0 matches.

### Step 4: Remove allow_dangerous_commands from quick-reference config table

In `docs/quick-reference.md`, locate the config table under the
`~/.config/blueprint/config.yaml` section. Remove the row:
```
allow_dangerous_commands: true|false   # default false
```

**Verify**: `grep -n "allow_dangerous" docs/quick-reference.md` returns 0 matches.

### Step 5: Optional — annotate dry_run as not yet active

In `docs/quick-reference.md`, the `dry_run` row (line 136) can stay for now,
but add a comment: `# parsed but not yet active` so users know it won't work
until Plan 009 is applied. Or remove it if you prefer conservative docs.

## Done criteria

- [ ] `grep -rn "\.ejs\.ts" README.md docs/` returns 0 matches
- [ ] `grep -rn "actionfolder" README.md docs/` returns 0 matches
- [ ] `grep -rn "allow_dangerous_commands" docs/` returns 0 matches
- [ ] `README.md` still renders correctly as markdown
- [ ] `docs/quick-reference.md` still renders correctly
- [ ] `plans/README.md` status row updated

## STOP conditions

- A step's verification shows unexpected matches (report with locations).
- Removing a line breaks the table formatting.

## Maintenance notes

When Plan 009 (wire dry_run) is complete, remove the "not yet active" note.
