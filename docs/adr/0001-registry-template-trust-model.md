# ADR 0001: Registry template trust model

- **Status:** Draft — maintainer ruling required
- **Date:** 2026-10-01
- **Decision owner:** Maintainer

## Context

The existing registry trust gate restricts EJS tag forms, not expression
semantics. `EjsSafety.isUnsafe` rejects control-flow and unescaped-output
tags, while `<%= ... %>` passes; EJS compiles interpolation contents to
JavaScript executed in-process. In particular:

- `TemplateRenderer.res:47` resolves `to:` through `ejs.renderString`,
  before the provenance check at `:244-245`, which gates the body only.
- `Expression.res` evaluates manifest prompt expressions without provenance
  or `isUnsafe` awareness.
- EJS expressions execute in-process. The existing test
  `EjsSafety_test.res` explicitly accepts `<%= 1 + 2 %>`.
- The plan's preliminary survey characterized repository `to:` values as
  simple dotted interpolation (`<%= path %>`, `<%= name %>` style). The
  Step 2 scan in this draft found exceptions in the examples: three values use
  `<%= h.snakeCase(name) %>`; see compatibility evidence below. This corrects
  the preliminary compatibility claim without changing the gate facts above.

These facts mean the current gate is a tag policy, not a restricted
expression language. A regular-expression filter over JavaScript expressions
would not provide that language boundary.

Plan 038's decisions of record (`plans/038-remote-template-trust-gate.md`,
lines 61–80) are: local templates remain fully trusted; the provenance marker
identifies marked/registry templates; marked templates receive the EJS tag
policy; hooks and `sh:` are not additionally gated there because allowlist
work in plans 035/036 bounds them; and `node:vm` was rejected as a false
sense of security.

### Install reality and severity honesty

Installation is a local copy that the user explicitly confirms, with the
default answer NO. There is no network installer today; “registry” means the
user's own `~/.config/blueprint/templates`. The practical attack surface is
therefore: **the user confirms a directory someone else gave them**. This
lowers practical severity compared with unattended network installation,
but does not make an expression gate meaningful or eliminate the need to be
accurate about trust.

## Options

### Option A — Honest trust

- **Mechanics:** State plainly that registry templates are trusted code.
  Rewrite the README safety wording. Make the existing gate advisory lint
  (for example, warn on control-flow tags), or remove it; retain the marker
  only as informational provenance.
- **Effort:** S.
- **Compatibility risk:** LOW. Existing template expressions continue to
  work; the restricted-tier promise disappears and users must review
  templates at install time.
- **Follow-up inherits:** Documentation and any chosen advisory/removal
  behavior. It must not describe registry templates as sandboxed or
  restricted.

### Option B — Real restricted profile

- **Mechanics:** For marked templates, replace `ejs.renderString` with a
  non-evaluating expression language: dotted identifiers resolved from the
  render context and string/number literals, with no general JavaScript.
  This applies to marked `to:`/`from:`/prompt expressions, not a regex filter
  over JavaScript. Apply a gate to every EJS-evaluated channel: body,
  `to:`, frontmatter values, and manifest expressions. Deny manifest hooks
  for marked generators, or require explicit confirmation for them.
- **Effort:** M–L; land in stages.
- **Compatibility risk:** MED–HIGH. Existing marked templates using
  arithmetic or helpers break. The enshrined `<%= 1 + 2 %>` test changes to
  **REJECTED** for the restricted profile.
- **Follow-up inherits:** The full channel inventory (body, `to:`, `from:`,
  prompt expressions, and manifest hooks); fail-closed handling at each
  channel; staged rollout and compatibility tests; and a single gated helper
  for template-authored strings so new evaluation sites cannot bypass the
  boundary. Do not try to obtain this behavior by extending the tag regex.

### Option C — Process isolation

- **Mechanics:** Render marked templates in a child process. Plan 038
  rejected `node:vm`; a child process is heavier but provides real process
  isolation rather than a VM sandbox.
- **Effort:** L+.
- **Compatibility risk:** MED, primarily process lifecycle, error surfacing,
  and platform quirks.
- **Follow-up inherits:** Child-process protocol, lifecycle and failure
  semantics, platform coverage, and the same inventory of evaluated
  channels. Given explicitly confirmed local installs, this is likely
  overkill.

## Prototype compatibility evidence (Step 2)

The inert scan walked 19 `to:` directives in `_templates/**` and
`examples/**`. Against the strict expression language and a sample context,
these three directives were rejected because they use helper calls:

- `examples/go-handler/new/handler.go.ejs.t` —
  `<%= package %>/<%= h.snakeCase(name) %>.go` — `h.snakeCase(name)` is a
  function call.
- `examples/python-fastapi/new/route.py.ejs.t` —
  `app/routes/<%= h.snakeCase(name) %>.py` — `h.snakeCase(name)` is a
  function call.
- `examples/python-fastapi/new/test_route.py.ejs.t` —
  `app/routes/<%= h.snakeCase(name) %>_test.py` — `h.snakeCase(name)` is a
  function call.

The scan also confirmed the related Go and YAML examples require `package`
and `environment` in the supplied context; those identifiers are valid
syntax and are accepted when present. The scan was run with these additional
sample keys, leaving the three helper calls as the actual syntax-level
rejections. Static frontmatter values (for example
`to: package.json` and `to: config.yaml`) pass as plain text; dynamic values
use text around `<%= dotted.identifier %>` or the helper-call form above.

## Advisor lean (not a ruling)

The advisor's initial lean was Option B's gate-first subset, landed in
stages. The compatibility scan found repository-owned helper-call `to:`
expressions, so the compatibility condition is already material: Option A's
honest trust model may be the safer landing unless the maintainer explicitly
accepts changing those templates to remove the helper calls or a staged
compatibility break. This is advice only; the maintainer owns the ruling.

## Chokepoint requirement

Whichever option is selected, centralize **template-authored string →
evaluator** behind one gated helper so new evaluation sites cannot skip the
gate. Keep the channel inventory explicit, including body, `to:`, `from:`,
prompt expressions, frontmatter values, and manifest hooks.

## Ruling

**DECIDED (maintainer, 2026-10-02): Option A — Honest trust.**

- **Decision:** Registry-installed (marked) templates are trusted code. The
  documentation must say so; the restricted-tier wording is retired. The
  provenance marker remains as informational provenance, and plan 038's tag
  gate remains in the code as an interim advisory check until the follow-up
  downgrades it to a warning (or removes it) — no behavioral change lands
  from this ADR itself.
- **Rationale:** (1) The prototype's compatibility scan found the deciding
  evidence the advisor lean required: repository-owned example templates
  already use JS helper calls (`h.snakeCase(name)`) in `to:` values, so a
  real restricted profile breaks real templates on day one. (2) Install is
  an explicitly confirmed local copy with no network installer; the trust
  question is review-at-install, which documentation should state honestly
  rather than answer with a tag lint. (3) Plan 038 deliberately made local
  templates trusted and rejected sandboxing; Option A completes that
  posture instead of extending it with an unenforceable promise.
- **Consequences:** (1) The README Safety section states the truth of this
  model (landed with this ADR). (2) Follow-up plan (small, S-effort):
  downgrade the marked-template gate to an advisory warning or remove it,
  keep the marker as informational provenance, update the enshrined
  `<%= 1 + 2 %>` test expectations, and drop the restricted-tier wording
  from any remaining docs (docs/api-reference.md, docs/setup.md if
  applicable). (3) The chokepoint requirement stands as guidance for any
  future trust work: centralize template-authored-string → evaluator behind
  one gated helper. (4) If a network installer is ever added, this ruling
  must be revisited — the install-reality premise is what makes Option A
  sound.
- **Prototype disposition:** `spike/050-trust-model-prototype` is parked,
  never merged; its scan results are recorded above and in
  `plans/README.md`.
