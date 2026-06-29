# Plan 002: Fix Frontmatter regex to accept CRLF line endings

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- src/domain/template/Frontmatter.res`
> If the file changed since this plan was written, read the current version
> and adjust the line references before proceeding.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

The frontmatter regex only matches `\n` (LF) line endings. Any template file
created or edited on Windows with `\r\n` (CRLF) endings fails frontmatter
parsing with "Missing or invalid frontmatter delimiter". The template is
silently skipped. This blocks Windows users from using the tool.

## Current state

**File**: `src/domain/template/Frontmatter.res`, line 17

```rescript
let frontmatterRegex: RegExp.t = /^---\n([\s\S]*?)\n---\n/
```

The `\n` before each section requires a bare LF. CRLF files have `\r\n`
sequence — the `\r` before `\n` causes the match to fail.

The regex is also used in line 102 for body extraction:
```rescript
let body = Js.String.replaceByRe(frontmatterRegex, "", content)
```

Both uses need the update.

**Convention**: ReScript PascalCase modules, snake_case values. `//` comments.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Build     | `pnpm res:build`         | exit 0              |
| Tests     | `pnpm res:test`          | all pass            |

## Scope

**In scope**: `src/domain/template/Frontmatter.res`

**Out of scope**: Any other regex or parsing logic

## Steps

### Step 1: Update the regex

Change line 17 from:
```rescript
let frontmatterRegex: RegExp.t = /^---\n([\s\S]*?)\n---\n/
```
to:
```rescript
let frontmatterRegex: RegExp.t = /^---\r?\n([\s\S]*?)\r?\n---\r?\n/
```

This makes the `\r` optional before every `\n`, accepting both `\n` (LF,
Unix/macOS) and `\r\n` (CRLF, Windows).

**Verify**: `pnpm res:build` — should compile without errors.

### Step 2: Run tests

**Verify**: `pnpm res:test` — all tests pass, especially Frontmatter_test.

### Step 3: Manual verification

Create a temp `.ejs.t` file with CRLF line endings and verify parsing works:

```bash
printf '---\r\nto: test.txt\r\n---\r\nhello' > /tmp/test_crlf.ejs.t
node -e "
const fs = require('fs');
const content = fs.readFileSync('/tmp/test_crlf.ejs.t', 'utf8');
const bytes = Buffer.from(content);
console.log('Has CRLF:', content.includes('\r\n'));
"
```

Then write a small ReScript test or use the compiled JS to run parse on it.

## Done criteria

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0; all Frontmatter tests pass
- [ ] A `.ejs.t` file with CRLF line endings is parsed successfully
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The code doesn't match the excerpts above (read the current file first).
- A step's verification fails twice after a reasonable fix attempt.

## Maintenance notes

This is a targeted regex change — it doesn't affect any other parsing logic.
The same pattern (`\r?\n` for optional carriage return) should be used in any
future regex that parses template headers.
