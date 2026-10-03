# Plan 050: Decide and document the registry template trust model

> **Executor instructions**: This is a DECISION/DESIGN plan, not a build
> plan. Its product is a written decision record plus (optionally) a
> throwaway prototype branch that measures feasibility — NOT a landed
> behavior change. Follow the steps in order; every "surface the decision"
> step means STOP and present to the maintainer. When done, update the
> status row for this plan in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 100b121..HEAD -- src/application/prompts/EjsSafety.res src/application/pipeline/TemplateRenderer.res src/application/prompts/Expression.res src/application/engine/EngineOrchestrator.res src/interfaces/cli/TemplateRegistry.res README.md plans/038-remote-template-trust-gate.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: L (design + prototype; a landed implementation is a follow-up plan)
- **Risk**: HIGH (touches the trust boundary every registry user relies on; compatibility risk for existing marked templates)
- **Depends on**: none (038 landed; this plan decides what comes AFTER 038)
- **Category**: direction
- **Planned at**: commit `100b121`, 2026-10-01

## Why this matters

README (`README.md:314`) tells users registry-installed (marked) templates
are "rendered only when they use safe EJS interpolation tags (`<%= %>`)".
That is not what the code provides. `<%= %>` tags pass the gate, but EJS
compiles the expression INSIDE them to JavaScript executed in-process via
`new Function` — the gate filters TAG SYNTAX, not expression semantics. On
top of that, the `to:` directive is EJS-evaluated BEFORE the gate runs, and
manifest prompt expressions and generator manifest hooks are never gated at
all. So the documented "restricted" tier is, in practice, the same trusted
tier with a lint rule. Either the documentation must tell the truth
(registry templates are trusted code), or the restricted profile must be
real. Plan 038 made these choices deliberately (rejected `node:vm`, left
hooks to allowlists) — this plan surfaces the accumulated decision for a
fresh ruling rather than silently drifting further.

## Current state

At `100b121`:

- `src/application/prompts/EjsSafety.res:4-15` — `isUnsafe` matches
  `<%(?![-=])` and `<%-`: only `<%= %>` passes. The comment claims
  "allowlist-equivalent in practice" — accurate FOR TAGS, not for
  expressions. `test/EjsSafety_test.res:28-30` enshrines `<%= 1 + 2 %>`
  (operators) as passing.
- `src/infrastructure/bindings/Ejs.res:23-25` — EJS compiles templates via
  `new Function` (check the binding's render path for the exact shape) —
  a passing `<%= expr %>` executes arbitrary JS with side effects; escaping
  affects OUTPUT only.
- `src/application/pipeline/TemplateRenderer.res:221-245` — the `to:`
  directive is resolved through `ejs.renderString` (via `resolveTargetPath`
  at `:47`) BEFORE the provenance gate, which runs on the BODY only
  (`hasProvenance && EjsSafety.isUnsafe(resolvedBody)`).
- `src/application/prompts/Expression.res:48-67` — manifest prompt
  expressions (`when:`, `default:`, option labels) evaluate via EJS with no
  provenance awareness (Phase0, pre-gate).
- `src/application/engine/EngineOrchestrator.res:44-56,231-256` — generator
  manifest hooks (`pre_generate`/`post_generate`) run with no provenance
  check anywhere (grep: provenance appears only in `TemplateRegistry.res`
  and `TemplateRenderer.res`). Allowlists bound them ONLY if the user
  configured `shell.tools` (permissive when unset —
  `src/infrastructure/hooks/Hooks.res:84-88`).
- `plans/038-remote-template-trust-gate.md:61-80` — the design decisions of
  record: local templates fully trusted; marker = provenance; marked
  templates get the tag policy; hooks/sh "NOT additionally gated here
  (allowlist work in plans 035/036 already bounds them)"; `node:vm`
  REJECTED (false sense of security).
- Install reality: `TemplateCopy.res:27-33` — install is a LOCAL copy the
  user explicitly confirms (default NO), naming the source path. There is
  NO network installer today; "registry" = the user's own
  `~/.config/blueprint/templates`. That lowers the practical severity of
  every channel (the user confirmed a local path they typed) — the decision
  should weigh this honestly.

## Commands you will need

| Purpose | Command | Expected on success |
|-----------|---------|---------------------|
| Compile (typecheck) | `pnpm res:build` | exit 0 |
| All tests | `pnpm res:test` | all pass |

`.res.mjs` artifacts are gitignored (in-source compilation) — build locally,
never commit them.

## Scope

**In scope** (the only files you should modify — and only in the
decision-record and prototype steps below):
- `docs/adr/` (create `docs/adr/0001-registry-template-trust-model.md` or
  the repo's established decisions location — none exists today, so create
  the ADR directory with this one record)
- `README.md` (Safety section — ONLY the wording the chosen decision
  requires; as part of the decision-execution step, after the maintainer
  rules)
- A throwaway prototype branch (deleted or parked after the decision —
  never merged by this plan)

**Out of scope** (do NOT touch, in any step of this plan):
- `EjsSafety.res`, `TemplateRenderer.res`, `Expression.res`,
  `EngineOrchestrator.res`, `Hooks.res` — implementation belongs to the
  FOLLOW-UP plan the chosen option generates, not this one.
- Plan 038's landed gate — keep functioning until the follow-up lands.
- Any sandbox/vm work — 038 rejected it; do not relitigate inside this plan.

## Git workflow

- Branch (prototype only): `spike/050-trust-model-prototype`
- The decision record itself: commit on `main` as
  `docs(adr): record registry template trust model decision`
- Do NOT push, merge the prototype, or open a PR unless instructed.

## Steps

### Step 1: Write the decision brief (READ-ONLY research + one document)

Draft `docs/adr/0001-registry-template-trust-model.md` with: context (the
Current state facts above, inlined), and the three options with evidence,
effort, and compatibility risk:

- **Option A — Honest trust.** Registry templates are trusted code. README
  rewritten to say so; the gate becomes an advisory lint (warn on
  control-flow tags) or is removed with the marker kept as informational.
  Effort S. Risk: LOW. Cost: the "restricted tier" promise disappears;
  users must review templates at install time only.
- **Option B — Real restricted profile.** For marked generators: a
  non-evaluating expression language (dotted identifiers into the render
  context + string/number literals; NO general JS — this REPLACES
  `ejs.renderString` for marked `to:`/`from:`/prompt expressions, it is not
  a regex filter on JS), the gate applied to every EJS-evaluated channel
  (body, `to:`, frontmatter values, manifest expressions), and manifest
  hooks DENIED (or explicit-confirmation-gated) for marked generators.
  Effort M-L. Risk: MED-HIGH (existing marked templates using arithmetic
  or helpers break; the enshrined `<%= 1 + 2 %>` test flips to REJECTED).
- **Option C — Process isolation.** Render marked templates in a child
  process (038 rejected `node:vm`; a child process is heavier but real).
  Effort L+. Risk: MED (lifecycle, error surfacing, platform quirks).
  Likely overkill for a local-confirmed install model.

Include the severity honesty note: install requires explicit local-path
confirmation; there is no network installer; the practical attack surface
is "user confirms a directory they were given by someone else."

**Verify**: the ADR draft exists with all three options and evidence;
`pnpm res:build` still exits 0 (no source touched).

### Step 2: Prototype Option B's expression gate (throwaway branch)

On `spike/050-trust-model-prototype`: implement ONLY the non-evaluating
expression evaluator for marked `to:` values (a tiny parser: dotted
identifiers + literals; everything else → `Error` naming the template and
the rejected expression). Run the repo's own templates
(`_templates/**`, `examples/**`) through it as marked and record which
break. Do NOT wire it into prompts/hooks/body in the prototype. Keep the
branch unmerged.

**Verify**: `pnpm res:build` → exit 0; `pnpm res:test` → all pass (the
prototype must be inert for unmarked templates); your report lists every
repo template expression the strict evaluator would reject.

### Step 3: Surface the decision (STOP — maintainer ruling required)

Present to the maintainer: the ADR draft, the prototype's compatibility
results, and the recommendation. Recommendation to carry (advisor's, not a
ruling): Option B's gate-first subset (non-evaluating expressions for
marked templates + marked-hook denial), landing in stages — but if the
compatibility results show real templates need JS expressions, Option A's
honest documentation is the safer landing. DO NOT choose on the
maintainer's behalf.

**Verify**: maintainer decision recorded in the ADR (Context/Decision/
Consequences format).

### Step 4: Execute the documentation half of the ruling

Whatever the ruling: update `README.md`'s Safety section to state the
truth of the chosen model (for A: "registry templates run with your
permissions — review at install"; for B: keep the restricted-profile
wording, now accurate). Commit the ADR + README together on `main`.

**Verify**: `pnpm res:test` → all pass; the ADR and README agree with each
other and with the CODE as it stands at the time of the commit.

## Test plan

- No production tests change in this plan (the prototype must be inert).
- The follow-up plan (Option A's README-only, or Option B's staged gates)
  owns the RED tests — e.g. a marked `<%= process.getBuiltinModule(...) %>`
  body/`to:`/expression must FAIL CLOSED there.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `docs/adr/0001-registry-template-trust-model.md` exists with all three options, evidence, and the recorded ruling
- [ ] The prototype branch exists (or its results are recorded if the maintainer rules before prototyping) and is NOT merged
- [ ] `README.md` Safety section matches the ruled model and the actual code
- [ ] `pnpm res:build` and `pnpm res:test` exit 0 (no source changes landed by this plan)
- [ ] `plans/README.md` status row updated, including which follow-up plan the ruling generates

## STOP conditions

Stop and report (do not improvise) if:

- The maintainer cannot be consulted (the ruling IS the deliverable — do
  not pick an option to unblock yourself).
- The prototype requires touching out-of-scope files to be wired (it
  shouldn't — it must stay inert for unmarked templates).
- 038's gate or tests have drifted such that the Current state facts no
  longer hold.

## Maintenance notes

- Whatever the ruling, the FOLLOW-UP implementation plan inherits: the
  expression-channel inventory (body, `to:`, `from:`, prompt expressions,
  manifest hooks) — the 2026-10-01 audit's "one trust-gate chokepoint"
  direction suggests centralizing "template-authored string → evaluator"
  behind a single gated helper so new eval sites cannot skip the gate.
- Do NOT accept "just extend the regex" as the follow-up: tag filtering
  cannot filter expression semantics; that is the entire finding.
- Plan 042 (project-hook scriptRoot) and plan 039 (`shell.enabled`) both
  narrow the hook channel independently of this ruling; they compose.
