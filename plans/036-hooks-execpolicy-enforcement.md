# Plan 036: Make hooks honor the documented ExecPolicy execution boundary

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0267337..HEAD -- src/infrastructure/hooks/Hooks.res src/domain/exec/ExecPolicy.res src/application/engine/EngineHooks.res test/Hooks_test.res test/HookContext_test.res README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (hooks are user-configured; removing shell interpretation must
  not break documented hook workflows)
- **Depends on**: plans/035 (establishes the tokenization contract reused here)
- **Category**: security
- **Planned at**: commit `0267337`, 2026-09-27

## Why this matters

`src/domain/exec/ExecPolicy.res:5-6` documents that "the same hybrid policy is
enforced at every execution boundary". That is false for hooks:
`Hooks.res` never calls `ExecPolicy.decide`; non-path, no-arg hook commands
(e.g. `pre_generate: "npm test"`) execute through `shell.execAsync` — full
shell interpretation — with only a timeout bound. The gates that DO exist
(timeout, path containment for `/`-containing commands, env filtering) are
reasonable, but the shell interpretation plus the false contract comment give
auditors and users an incorrect security model. This plan makes the code match
a defensible contract: hooks run via `execFile` with tokenized args (same rule
as plan 035 establishes for inline `sh:` commands), honor the tools allowlist
when configured, and the ExecPolicy comment is corrected to describe reality.

## Current state

At `0267337`:

- `src/infrastructure/hooks/Hooks.res:173-186` — `run` takes 10 labeled
  params; NO `shellConfig`/allowlist parameter exists. Called from
  `src/application/engine/EngineHooks.res:54`.
- `src/infrastructure/hooks/Hooks.res:61` — uses `ExecPolicy.defaultTimeout`
  (default 5s bound at `:204` per audit).
- `src/infrastructure/hooks/Hooks.res:101-104` — path-like commands (contain
  `/`) get tree containment + `execFile` (no shell). SAFE already.
- `src/infrastructure/hooks/Hooks.res:75,146` — non-path no-arg commands go
  through `shell.execAsync` = shell interpretation. THE GAP.
- `src/infrastructure/hooks/Hooks.res:216-232` — `run` executes whenever
  `config.hooks` specifies a command (config presence = the opt-in; no prompt).
- `src/infrastructure/hooks/Hooks.res:49` — env via `EnvFilter.buildSafeEnv`
  (default-deny: `PATH`, `HOME` + config `shell.env` keys; metacharacter
  filtering at `EnvFilter.res:28-40`).
- `src/domain/exec/ExecPolicy.res:5-6` — the overbroad contract comment.
- `test/Hooks_test.res`, `test/HookContext_test.res` — existing coverage to
  keep green.

### Design decisions (already made — do not relitigate)

1. Hooks remain opt-in via their presence in the user's config (current
   documented behavior — do NOT add a `shell.enabled` hard gate that would
   silently stop existing users' hooks).
2. Non-path hook commands switch from `shell.execAsync` to `execFile` with
   whitespace-tokenized args, applying plan 035's metacharacter-rejection
   contract verbatim. Hooks needing shell features must use a script path
   (already supported, already contained).
3. If a tools allowlist is configured, the hook's first token must be
   allowlisted — same binary-allowlisting as inline commands. Empty/unset
   allowlist keeps hooks permissive-but-shellfree (their config-presence
   opt-in distinguishes them from template-authored `sh:` commands).

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile (= typecheck) | `pnpm res:build` | exit 0 |
| Run all tests | `pnpm res:test` | all pass |
| Run hook tests only | `npx retest ./test/Hooks_test.res.mjs ./test/HookContext_test.res.mjs` | all pass |

## Scope

**In scope** (the only files you should modify):
- `src/infrastructure/hooks/Hooks.res` — execution path + optional allowlist param.
- `src/application/engine/EngineHooks.res` — thread the new param (call at `:54`).
- `src/domain/exec/ExecPolicy.res` — correct the contract comment ONLY.
- `test/Hooks_test.res` — new cases.
- `README.md` — Hooks section: document the execution contract.

**Out of scope** (do NOT touch):
- `ExecPolicy.decide` logic (its args-bypass and ShellExact semantics are
  settled and tested).
- `EnvFilter`, `HookContext` (working as designed).
- Hook lifecycle/ordering, the 10-param signature cleanup (tracked separately
  as debt; only ADD the one param you need).

## Git workflow

- Branch: `fix/hooks-exec-boundary`
- Conventional commits: `fix(...)`, `docs(...)`, `test(...)`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Execute non-path hook commands via execFile + tokenization

Commit message: `fix(hooks): run non-path hook commands without shell interpretation`

In `Hooks.res` (`:75,146` exec sites):

1. Add a shared helper (local to `Hooks.res`): tokenize command on whitespace;
   reject tokens containing metacharacters/quotes (`&& ; | $ ( ) < > \` " ' \n`)
   with an error naming the hook and guiding to a script path.
2. Replace `shell.execAsync(fullCommand)` with the `execFile` port call using
   first token as file, remainder as args (mirror how path-like commands
   already execute at `:101-104`). Timeout and env handling unchanged.

**Verify**: `pnpm res:build` → exit 0; `npx retest ./test/Hooks_test.res.mjs` → existing tests pass or fail ONLY where they asserted shell-string behavior (update those expectations per the new contract).

### Step 2: Optional allowlist enforcement

Commit message: `fix(hooks): honor tools allowlist when configured`

1. Add `~toolsAllowlist: option<array<string>>=?` to `Hooks.run` (`:173-186`)
   and thread from `EngineHooks.res:54` (source: the shell config's tools
   list; locate via `grep -n "tools" src/domain/` config types — if the
   plumbing is not reachable from EngineHooks, STOP).
2. When `Some(list)` and list is non-empty: non-path hook commands whose first
   token is not in the list are rejected with an error mentioning
   `tools allowlist`. `None`/empty → permissive (design decision 3).

**Verify**: `pnpm res:build` → exit 0.

### Step 3: Correct the ExecPolicy contract comment; document hooks

Commit message: `docs(exec): state per-boundary policy accurately; document hook execution contract`

1. `ExecPolicy.res:5-6` — replace with a precise description: policy module
   for tool/script/hook boundaries; which boundaries consult the allowlist
   (inline commands: binary allowlist + execFile; hooks: allowlist when
   configured; ToolCall no-args: ShellExact; ToolCall with args: ExecFile
   bypass by design).
2. README Hooks section: hooks run tokenized via `execFile` (no shell), with
   timeout, filtered env, path containment for script paths, and allowlist
   enforcement when `shell.tools` is configured.

**Verify**: `pnpm res:build` → exit 0 (comment-only change compiles).

### Step 4: Tests

Commit message: `test(hooks): execFile execution, metachar rejection, allowlist gating`

Add to `test/Hooks_test.res`:

1. Non-path command `npm test` → execFile mock receives file `npm`, args `["test"]` (no shell).
2. Command with `&&` → rejected, error names the hook.
3. `~toolsAllowlist=Some(["npm"])` + command `git status` → rejected mentioning `tools allowlist`.
4. `~toolsAllowlist=None` + command `npm test` → executes (permissive default).
5. Path-like hook command → unchanged containment behavior (regression guard).

**Verify**: `npx retest ./test/Hooks_test.res.mjs ./test/HookContext_test.res.mjs` → all pass; `pnpm res:test` → all pass.

## Test plan

- The five cases above, modeled on existing `Hooks_test.res` mock style.
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the 5 new tests
- [ ] `grep -n "execAsync" src/infrastructure/hooks/Hooks.res` returns no matches on the non-path command path
- [ ] `ExecPolicy.res` comment no longer claims uniform enforcement at every boundary
- [ ] README documents the hook execution contract
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Drift vs the excerpts above (since `0267337`), or plan 035 changed the
  tokenization helper location (reuse it; if it is not exported and sharing
  requires touching a third module, duplicating the helper locally in Hooks.res
  is acceptable — note it).
- The tools-allowlist config is not reachable from `EngineHooks.res` without
  threading through more than one intermediate module (report the plumbing).
- Existing hook tests assert shell-string semantics (`&&`, pipes) as DESIRED
  behavior for non-path commands (surface the conflict — the README may
  document features this change removes).
- `Hooks.run`'s 10 existing params don't match the audit (signature drifted).

## Maintenance notes

- The 10→11 param growth is deliberate debt; the structural fix (a context
  record / `Ports.deps` passthrough) is tracked as architecture debt, not here.
- Reviewer should scrutinize: env vars still reach the execFile'd hook
  (buildSafeEnv preserved) and the timeout still applies.
