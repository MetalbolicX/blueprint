# Plan 038: Add a trust gate for remote/registry-installed templates

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 0267337..HEAD -- src/interfaces/cli/TemplateRegistry.res src/interfaces/cli/TemplateRegistry.resi src/application/prompts/EjsSafety.res src/infrastructure/rendering/Renderer.res test/TemplateRegistry_test.res README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED (new user-facing prompt + a render-time gate; must not break
  local template flows)
- **Depends on**: none (but land AFTER 033-037 so security review lands in one
  coherent series)
- **Category**: security
- **Planned at**: commit `0267337`, 2026-09-27

## Why this matters

Template rendering uses full EJS: `src/infrastructure/rendering/Renderer.res:60`
calls `Bindings.Ejs.render(tmpl.body, ...)` with no tag restrictions — EJS
compiles the body to a JS function, so a template body IS in-process code.
That is fine for local, user-authored templates (Hygen parity). But the
registry install path lets users install templates from the network, and a
repo-wide audit found NO provenance layer anywhere in `src/` (no signature,
no integrity check, no trust prompt — grep for
`signature|integrity|trust` matches only an unrelated SsrfGuard comment).
Chain: install remote template → `blueprint generate` → arbitrary code exec
in the CLI process (with the user's env, however filtered). This plan adds
the missing trust boundary: an explicit confirmation at install time plus a
provenance marker, and a render-time EJS safety gate for remote-provenance
templates only.

## Current state

At `0267337`:

- `src/infrastructure/rendering/Renderer.res:60` — `Bindings.Ejs.render(tmpl.body, data->Obj.magic)`. Ungated. The WS4-stripped context at `Renderer.res:6-15` limits DATA exposure, not CODE execution.
- `src/application/prompts/EjsSafety.res:9-15` — `_hasUnsafeEjsTags` gate
  (allows only `<%= %>`; rejects control-flow `<%` and unescaped `<%-`).
  Its ONLY callers are prompt-expression paths: `Expression.res:48,57`.
  Documented as mirroring the Go original's prompt resolver.
- Registry surface: `src/interfaces/cli/TemplateRegistry.res` (+ `.resi`) —
  template copy/list/remove commands; the install/download flow lives at or
  near this module (the exact install entrypoint was NOT pinned by the audit —
  Step 1 locates it). `test/NpmPackInstall_test.res` exists and mocks exec
  via an injected `%raw` stub (mock-based, no live network).
- Global templates root: `~/.config/blueprint/templates`
  (`src/interfaces/cli/Utils.res:1-4`); registry entries are directories under it.
- Fetch layer: `src/infrastructure/fetcher/SsrfGuard.res` resolves hostnames
  pre-connect and blocks loopback/RFC1918/link-local/ULA/metadata IPs
  (tested at `test/SsrfGuard_test.res:11-140,188-290`). Fetch is hardened;
  everything AFTER fetch is trust-free.
- Prompts infrastructure exists for interactive confirmation (PromptResolver,
  Readline bindings) — reuse it for the install confirmation.

### Design decisions (already made — do not relitigate)

1. Local templates (`./_templates`, project dirs) remain fully trusted — no
   gate, no prompt (Hygen parity; breaking change otherwise).
2. Provenance marker: a sidecar file `.blueprint-provenance` written into the
   installed template's directory at install time, containing the source
   URL/name and install timestamp. Absence of the file = local = trusted.
3. Remote-provenance templates are rendered with the `EjsSafety` tag policy
   (only `<%= %>` allowed); `<%`/`<%-` in a remote template → hard error
   naming the template and the offending tag. `sh:` directives and hooks from
   remote templates are NOT additionally gated here (allowlist work in plans
   035/036 already bounds them); this plan's gate is the EJS code-exec vector.
4. Rejected alternative: `node:vm` sandboxed rendering (bigger surface,
   false sense of security) — out of scope.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| ReScript compile (= typecheck) | `pnpm res:build` | exit 0 |
| Run all tests | `pnpm res:test` | all pass |
| Run registry tests only | `npx retest ./test/TemplateRegistry_test.res ./test/EjsSafety_test.res.mjs` | all pass |
| Locate install flow | `grep -rn "npm pack\|npm i \|npm install\|registry" src/interfaces/cli/` | matches in TemplateRegistry area |

## Scope

**In scope** (the only files you should modify):
- `src/interfaces/cli/TemplateRegistry.res` (+ `.resi`) — install-time prompt
  + provenance marker write (or the actual install module found in Step 1).
- `src/application/prompts/EjsSafety.res` — export/lift the unsafe-tag check
  for reuse (keep prompt behavior identical).
- `src/infrastructure/rendering/Renderer.res` — provenance-aware gate.
- The module that owns template discovery/context if provenance must flow to
  the renderer (locate in Step 2; prefer reading the sidecar at render time
  from the template dir to avoid threading new state).
- `test/TemplateRegistry_test.res` (+ new test file if cleaner).
- `README.md` — Safety section: the trust model.

**Out of scope** (do NOT touch):
- Local template rendering behavior.
- SsrfGuard/fetch internals.
- Sandboxing, signatures/checksums (a checksum only proves the same bytes —
  no identity; a signature scheme needs key distribution — future work).
- Plans 035/036 allowlist semantics.

## Git workflow

- Branch: `feat/remote-template-trust-gate`
- Conventional commits: `feat(...)`, `test(...)`, `docs(...)`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Pin the install entrypoint (READ-ONLY recon)

No commit. Run the locate greps above plus
`grep -rn "install\|copy" src/interfaces/cli/TemplateRegistry.resi`. Identify
the exact function that writes downloaded template content into the global
registry root. Map: where content lands on disk, and what metadata (if any)
accompanies it.

If an existing prompt/signature/integrity check already exists on that path —
STOP and report (finding refuted; plans/README.md row should be REJECTED).

### Step 2: Provenance marker at install time + confirmation prompt

Commit message: `feat(registry): confirm remote installs and record provenance`

1. In the install flow: before writing content, prompt the user naming the
   source (URL/registry name) and asking to confirm (reuse the Readline port /
   PromptResolver pattern; default NO on non-TTY — abort with a clear message
   and a `--yes` style flag to bypass if a flag-parsing seam already exists;
   otherwise non-interactive install fails closed).
2. On confirm, write `.blueprint-provenance` into the installed template dir:
   source identifier + timestamp as plain YAML or key: value lines.

**Verify**: `pnpm res:build` → exit 0.

### Step 3: Render-time gate for remote-provenance templates

Commit message: `feat(render): enforce EJS safety policy on remote-provenance templates`

1. Lift `_hasUnsafeEjsTags` to a public `isUnsafe`/`assertSafe` in
   `EjsSafety.res` (prompt callers unchanged).
2. In `Renderer.res` render path: determine the template's directory
   (available on the template being rendered); if
   `<templateDir>/.blueprint-provenance` exists (fs port `fileExists`), run
   the safety check on the body BEFORE `Ejs.render`; on unsafe tags return an
   error naming the template path and the offending tag pattern, advising the
   user to inspect the template or remove the provenance trust only by
   deleting the marker after review.
3. Local templates (no marker) render exactly as today.

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → all existing tests pass (none of the repo's own templates carry the marker).

### Step 4: Tests

Commit message: `test(registry): install confirmation, provenance marker, render gate`

Model on `test/TemplateRegistry_test.res` and the mocked-exec style of
`test/NpmPackInstall_test.res`:

1. Install flow with declining prompt → no content written.
2. Install flow with confirming prompt → content written AND
   `.blueprint-provenance` exists with the source string.
3. Render a template whose dir contains `.blueprint-provenance` and whose
   body has `<% if %>` → `Error` naming the template.
4. Same body WITHOUT the marker → renders (local trust unchanged).
5. Remote-provenance body with only `<%= name %>` → renders.

**Verify**: `pnpm res:test` → all pass.

### Step 5: Document the trust model

Commit message: `docs(safety): document local vs remote template trust model`

README Safety section: local templates are fully trusted; registry-installed
templates are confirmed at install time, marked with provenance, and rendered
with a restricted EJS tag policy (`<%= %>` only); removal instructions.

**Verify**: `grep -n "provenance" README.md` → at least one hit.

## Test plan

- The five cases above.
- Full-suite gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the 5 new tests
- [ ] A template dir containing `.blueprint-provenance` with control-flow tags fails to render with a clear error
- [ ] The same template WITHOUT the marker renders unchanged
- [ ] README Safety section documents the trust model
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- Step 1 finds an existing trust gate on the install path (finding refuted).
- The install flow has MULTIPLE write paths making marker placement ambiguous
  (surface for design instead of choosing one).
- The renderer cannot see the template's source directory at render time
  (template records lack the dir) — report the type surface; do not thread
  provenance through 3+ modules (that is a design change).
- The interactive-prompt infrastructure cannot fail closed on non-TTY.

## Maintenance notes

- The marker is advisory state, not a security boundary against a local
  attacker (they can delete it) — it bounds REMOTE content only. Say exactly
  this in the README.
- Future: registry-side checksums pinned by the user (`blueprint template add
  --pin <sha>`) would strengthen this; key-signature schemes need a story for
  key distribution first.
- Reviewer should scrutinize: no remote-content path reaches `Ejs.render`
  without the marker check; the prompt cannot be auto-accepted in CI contexts.
