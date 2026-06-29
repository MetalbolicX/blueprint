# Plan 010: Add coverage tooling

> **Executor instructions**: Follow this plan step by step. When done, update
> the status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 3a6df55..HEAD -- package.json`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (infrastructure for other test plans)
- **Category**: tests
- **Planned at**: commit `3a6df55`, 2026-06-29

## Why this matters

The test runner (`retest`) has no built-in coverage instrumentation. After any
change, there's no way to know which code paths went untested. Adding `c8`
provides line/branch/function coverage data that drives focused test writing.
It's a prerequisite for Plans 011 (ShellExecutor tests) and for any future
coverage-based quality gates.

## Current state

**package.json** scripts:
```json
{
  "res:test": "retest ./test/*.res.mjs"
}
```

No coverage tool in devDependencies. No `.c8rc` config.

ReScript compiles `.res` → `.res.mjs` in-source. The `.res.mjs` files are the
executed JavaScript. `c8` instruments JavaScript — it will instrument the
`.res.mjs` output. Source mapping back to `.res` requires `--src` or similar.

## Commands you will need

| Purpose             | Command                  | Expected on success |
|---------------------|--------------------------|---------------------|
| Install             | `pnpm add -D c8`         | exit 0              |
| Coverage test run   | `pnpm res:test:coverage` | exit 0, report shown |
| Coverage check      | `pnpm res:test:coverage:check` | exit 0         |

## Scope

**In scope**: `package.json` — add devDependency and scripts

**Out of scope**:
- Any source code changes
- CI workflow changes
- Adding coverage thresholds that fail on current coverage (start lenient)

## Steps

### Step 1: Install c8

```bash
pnpm add -D c8
```

### Step 2: Add coverage scripts to package.json

Add these to the `scripts` object:
```json
"res:test:coverage": "c8 pnpm res:test",
"res:test:coverage:check": "c8 --check-coverage --lines 50 --functions 50 --branches 40 pnpm res:test"
```

The thresholds are deliberately low — the goal is to establish the
infrastructure, not to enforce quality gates immediately. Adjust after
the first real coverage report.

### Step 3: First coverage run

```bash
pnpm res:test:coverage
```

This should run all tests and produce a coverage summary. Note which files
have low coverage — those are candidates for targeted test additions.

### Step 4: Verify the check

```bash
pnpm res:test:coverage:check
```

Should exit 0 with current coverage levels.

## Done criteria

- [ ] `pnpm res:test:coverage` exits 0 and prints coverage report
- [ ] `pnpm res:test:coverage:check` exits 0
- [ ] `c8` listed in devDependencies in package.json
- [ ] No files outside the in-scope list are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- A verification fails (c8 not compatible with retest runner — if so, try
  `c8 --reporter=text --reporter=lcov` or use `node --experimental-test-coverage`
  as a fallback).
- Coverage report shows 0% on files that clearly have tests (config issue —
  report and stop).

## Maintenance notes

c8 is the simplest ESM-compatible coverage tool. If it proves incompatible
with `retest`, alternatives are:
- `node --experimental-test-coverage` (Node 22+ built-in)
- `nyc` with `--experimental-monorepo` flags

The `.res.mjs` files in the source tree are covered by `.gitignore` so coverage
reports won't be committed.
