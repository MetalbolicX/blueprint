# Plan 054: Make the registry provenance gate advisory (ADR 0001 Option A execution)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat ee418f4..HEAD -- src/application/pipeline/TemplateRenderer.res src/application/prompts/EjsSafety.res test/TemplateRenderer_test.res test/EjsSafety_test.res README.md`
> Plan 050's ADR (`a58a627`) ruled this follow-up; `ee418f4` is the commit
> this plan was written at. If any in-scope file changed since, compare the
> "Current state" excerpts against the live code; on a mismatch, treat it as
> a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (behavior loosening only: marked templates with control-flow
  tags render instead of failing, with a warning)
- **Depends on**: plan 050 (ADR 0001, ruled Option A — honest trust); merged
  to main
- **Category**: direction (follow-up owned by the ADR ruling)
- **Planned at**: commit `ee418f4`, 2026-10-02

## Why this matters

ADR 0001 (maintainer ruling, Option A — honest trust) retired the
restricted-tier promise: registry templates are trusted code, review happens
at install. Plan 050 landed the documentation half but deliberately left the
code gate functioning "until the follow-up downgrades it". This plan is that
follow-up: the gate stops BLOCKING marked templates and becomes an advisory
warning, so the code finally matches the documentation. Today the two
disagree: the README says templates run with your permissions (and review is
at install), while a marked template using a control-flow tag still hard-fails
at generate time with a "blocked by the provenance gate" error.

## Current state

At `a58a627` (post-merge main):

- `src/application/pipeline/TemplateRenderer.res:243-251` — the gate:
  `provenancePath = path.join(path.dirname(template.sourcePath), ".blueprint-provenance")`;
  `hasProvenance = await fs.fileExists(provenancePath)`;
  `unsafe = hasProvenance && EjsSafety.isUnsafe(resolvedBody)`; when unsafe →
  `Error("Registry-installed template was blocked by the provenance gate: " ++ ...inspect the template before removing its .blueprint-provenance marker.")`.
- `test/TemplateRenderer_test.res:41+` — suite "TemplateRenderer provenance
  gate": marked-template cases asserting the blocking Error (message contains
  `"provenance gate"`, e.g. `:64`).
- `test/EjsSafety_test.res:28-30` — enshrines `<%= 1 + 2 %>` as safe. The
  predicate `EjsSafety.isUnsafe` is UNCHANGED by this plan (it remains the
  advisory's detector); only the gate's CONSEQUENCE changes.
- `src/application/pipeline/TemplateRegistry.res` (plan 046) — install-time
  marker guards (symlink/forged-marker refusal) keep the marker truthful.
  Untouched. The marker stays informational provenance per ADR 0001.
- `Console.warn` is the module's established advisory channel
  (TemplateRenderer already warns on cleanup failures).
- README.md Safety section already states the honest model (plan 050) and
  links ADR 0001; grep confirms no other doc mentions the restricted tier.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |
| Focused tests | `npx retest ./test/TemplateRenderer_test.res.mjs ./test/EjsSafety_test.res.mjs` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify):
- `src/application/pipeline/TemplateRenderer.res`
- `test/TemplateRenderer_test.res`

**Out of scope** (do NOT touch):
- `EjsSafety.res` / `EjsSafety_test.res` — the predicate stays; it is the
  advisory's detector and its unit tests are unaffected.
- `TemplateRegistry.res` install guards (plan 046) — markers must stay
  truthful at install time.
- `Hooks.res`, `Expression.res`, `EngineOrchestrator.res` — the other
  ungated channels stay ungated; ADR 0001 ruled trust, not more gating.
- Any doc — README already matches the ruled model.

## Git workflow

- Branch: `chore/054-advisory-provenance-gate` (from `main`)
- Conventional commits, e.g. `chore(renderer): make the registry provenance gate advisory`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Flip the gate from blocking to warning

In `TemplateRenderer.res` (:243-251): keep the `provenancePath`/`hasProvenance`
/`unsafe` computation exactly; replace the `if unsafe { Error(...) }` arm with:

```rescript
if unsafe {
  Console.warn(
    "Advisory: registry template uses EJS control-flow tags (<% or <%-): "
    ++ template.sourcePath
    ++ ". Registry templates run with your permissions — review generators at install (ADR 0001).",
  )
}
```

and render unconditionally (the `else` arm's body becomes unconditional).
Keep `EjsSafety.isUnsafe` as the detector. The warning text names the file
and states the honest model; do not mention "removing the marker" as a
workaround anymore (the marker is informational now).

**Verify**: `pnpm res:build` → exit 0.

### Step 2: Flip the tests (RED→GREEN)

1. RED FIRST: before touching the source, change the blocking assertions in
   the "TemplateRenderer provenance gate" suite: a marked template with a
   control-flow tag must now RESOLVE (rendered output produced) AND emit a
   `Console.warn` containing `"Advisory: registry template"` and the template
   path (capture warnings the way `test/Engine_test.res`'s
   `withCapturedWarnings` helper does). Run focused — capture the RED
   (tests fail against the still-blocking gate).
2. Apply Step 1 → GREEN.
3. Keep/adjust the marked-template happy-path case: it must still pass and
   must NOT warn (no control-flow tags → no advisory).
4. Unmarked-template behavior is untouched (no provenance check warning).

**Verify**: `npx retest ./test/TemplateRenderer_test.res.mjs ./test/EjsSafety_test.res.mjs` → all pass; `pnpm res:test` → all pass (known Phase2 signal flake may fire once: one rerun allowed, disclose; never pipe the runner through `tail` when chaining — check the exit code).

## Test plan

- Flipped blocking→advisory cases (warn contains the path; render succeeds).
- Happy-path marked case: no warning.
- EjsSafety predicate suite untouched and green.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm res:build` exits 0
- [ ] `pnpm res:test` exits 0 including the flipped gate cases
- [ ] A marked control-flow-tag template RENDERS and warns (test-asserted)
- [ ] A marked simple template renders WITHOUT warning (test-asserted)
- [ ] `grep -rn "blocked by the provenance gate" src/ test/` returns nothing
- [ ] No files outside the in-scope list are modified (`git status --short`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report (do not improvise) if:

- The gate's Error arm is load-bearing somewhere other than
  TemplateRenderer_test (grep `provenance gate` across src/ and test/ first;
  any other consumer → surface before flipping).
- Flipping the gate changes any TemplateRegistry/046 install-guard test
  (install-time checks are a different mechanism — they must stay green).

## Maintenance notes

- ADR 0001 remains the decision of record; this plan executes its
  "downgrade to advisory" branch. Full gate REMOVAL (deleting
  `EjsSafety.isUnsafe` and the marker check) was the rejected alternative —
  the advisory keeps install-time signal at ~zero cost.
- If a future plan reintroduces any restricted tier, it must supersede
  ADR 0001 explicitly (new ADR), not silently re-tighten.
- The `unsafe` computation stays in place even though its only effect is the
  warning — it is the seam a future stricter model would re-arm.
