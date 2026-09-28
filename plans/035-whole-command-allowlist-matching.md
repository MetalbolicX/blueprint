# Plan 035: Match the inline-command allowlist against the whole command, not the first token

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0267337..HEAD -- src/application/pipeline/ShellExecutor.res src/domain/exec/ExecPolicy.res test/ShellExecutor_test.res test/ExecPolicy_test.res README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (stricter semantics; configs relying on first-token matching
  with multi-word commands will start failing — intentional, must be documented)
- **Depends on**: plans/034 (same file; land 034 first)
- **Category**: security
- **Planned at**: commit `0267337`, 2026-09-27

## Why this matters

The `shell.tools` allowlist is the config gate users rely on to bound what
template `sh:` directives may execute. For inline commands it currently
compares only the FIRST whitespace token against the allowlist, then hands the
FULL string to `child_process.exec` — i.e. the shell interprets everything
after the first token. An allowlist entry `git` admits `git status &&
<anything>`. Templates author the `sh:` string (potentially registry-sourced,
see plan 038), so the gate is materially weaker than advertised. No existing
test covers trailing content after an allowlisted command (verified: all
allowlist tests at `0267337` use bare single-word commands).

## Current state

At `0267337`:

- `src/application/pipeline/ShellExecutor.res:145-155` — the InlineCommand
  branch splits the command on `" "`, compares element `[0]` against
  `tool.command` entries, and on match proceeds.
- `src/application/pipeline/ShellExecutor.res:162` — the full unmodified
  string is then passed to `execShellCommand` → `exec`
  (`src/infrastructure/bindings/NodeJs/ChildProcess.res:26-31,116-122`),
  which parses it with a shell.
- `src/domain/exec/ExecPolicy.res` — the policy module. `decide` at `:37-44`:
  the `Some(structuredArgs)` branch returns `ExecFile` WITHOUT consulting the
  allowlist (documented at `:17-31` and codified in
  `test/ExecPolicy_test.res:25,69` — this args-bypass is BY DESIGN, do not
  change it in this plan). The `None` branch (`:40-44`) does exact full-string
  matching (`ShellExact`) against the allowlist.
- `src/application/pipeline/ShellExecutor.res:108-115` — the ToolCall path
  executes structured args via `execFile` (no shell) — the safe pattern to reuse.
- `src/application/pipeline/ShellExecutor.res:138-143` — inline commands are
  additionally gated by `shellConfig.enabled` (default deny); preserve that.
- Tests asserting current behavior: `test/ShellExecutor_test.res:463`
  ("command not in allowlist returns Error mentioning 'tools allowlist'") —
  keep the error message wording containing `tools allowlist`.

### Design decision (already made — do not relitigate)

Chosen fix: allowlist the BINARY (first token) but execute via `execFile` with
tokenized args — preserving "allowlist the tool name" semantics for existing
configs while removing shell interpretation of everything after it. Exact
whole-string matching was rejected (breaks every `tool status`-style command);
keeping `exec` was rejected (unfixable).

Tokenization contract: split on whitespace. If ANY token contains shell
metacharacters or quotes (`&& ; | $ ( ) < > \` " ' \n`), REJECT with an error
guiding the author to use a ToolCall with structured args. Templates needing
quoting/interpolation must use ToolCall, which already runs `execFile`.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile (= typecheck) | `pnpm res:build` | exit 0 |
| Run all tests | `pnpm res:test` | all pass |
| Run shell tests only | `npx retest ./test/ShellExecutor_test.res.mjs ./test/ExecPolicy_test.res.mjs` | all pass |

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/ShellExecutor.res` — InlineCommand branch.
- `test/ShellExecutor_test.res` — new rejection cases.
- `README.md` — one paragraph in the Safety/shell section documenting the
  tokenization contract (if a "tools allowlist" paragraph exists; locate via
  `grep -n "allowlist" README.md`).

**Out of scope** (do NOT touch):
- `ExecPolicy.res` semantics (args-bypass is by-design; `ShellExact` for
  ToolCall no-args stays as-is).
- Hooks (plan 036), timeout (plan 034).
- Any sandboxing/allowlist-globbing enhancement (`git*`-style patterns).

## Git workflow

- Branch: `fix/whole-command-allowlist`
- Conventional commits: `fix(...)`, `test(...)`, `docs(...)`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Tokenize-and-execFile the inline command path

Commit message: `fix(shell): execute allowlisted inline commands without shell interpretation`

In `ShellExecutor.res` InlineCommand branch (`:145-162`):

1. Keep the first-token allowlist check exactly as is (binary allowlisting).
2. Tokenize the full command on whitespace. Reject if any token contains a
   metacharacter/quote from the set above — error message must contain
   `tools allowlist` and guide to ToolCall structured args.
3. On pass, execute via the same `execFile`-style path ToolCall uses
   (`:108-115`, `execToolAsync`): first token as file, remaining tokens as
   args array. Drop the `execShellCommand` call for this branch.

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Tests — trailing content, exact behavior, regression

Commit message: `test(shell): reject shell metacharacters after allowlisted command`

Add to `test/ShellExecutor_test.res`:

1. `command = "git status && curl evil"`, allowlist `["git"]` → `Error`
   mentioning `tools allowlist` (the headline regression).
2. `command = "git status"` with allowlist `["git"]` → executes via execFile
   mock; assert the received file is `git` and args are `["status"]`.
3. `command = "git status"`, allowlist `["eslint"]` → `Error` (unchanged
   rejection).
4. `command = "echo \"a b\""` (quote in token) with `echo` allowlisted →
   `Error` guiding to ToolCall.

Also confirm no existing allowlist test asserted first-token+exec behavior with
trailing content (audit says none exist; if one does and now fails, update its
EXPECTATION per this plan's contract — do not revert the fix).

**Verify**: `npx retest ./test/ShellExecutor_test.res.mjs ./test/ExecPolicy_test.res.mjs` → all pass.

### Step 3: Document the contract

Commit message: `docs(safety): document inline command tokenization and allowlist scope`

In README.md's safety/shell section: state that allowlisted inline commands
run the allowlisted binary with whitespace-separated args via `execFile` (no
shell), and that quoting/interpolation requires ToolCall structured args.

**Verify**: `grep -n "execFile\|structured args" README.md` → at least one hit in the safety section.

## Test plan

- The four cases above; mock style per existing tests at
  `test/ShellExecutor_test.res:327,361,463`.
- Full suite: `pnpm res:test`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the 4 new tests
- [ ] The InlineCommand branch no longer calls `execShellCommand` (`grep -n "execShellCommand" src/application/pipeline/ShellExecutor.res` — remaining call sites, if any, are outside this branch or gone entirely after plan 034)
- [ ] README safety section documents the tokenization contract
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Drift vs the excerpts above (since `0267337`), especially if plan 034 already
  reshaped this branch (reconcile excerpts first).
- An existing test explicitly asserts shell interpretation of trailing inline
  content as DESIRED behavior (surface the conflict; do not silently change it).
- `ExecPolicy.decide`'s no-args branch turns out to be on the InlineCommand
  call path (the audit found the check is local to ShellExecutor — if `decide`
  already gates this branch, the fix belongs in `ExecPolicy.res` instead; stop
  and report the actual wiring).

## Maintenance notes

- If a future need arises for quoted args in inline commands, extend the
  tokenizer (e.g. shlex-style) — the security property to preserve is "no
  shell string ever reaches `exec`".
- Reviewer should scrutinize: the metacharacter set and that the execFile call
  uses the allowlisted binary exactly as first token (no path search surprises
  — `execFile` resolves via PATH, same as before).
