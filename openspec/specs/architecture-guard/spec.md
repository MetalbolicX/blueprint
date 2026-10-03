# Architecture Guard Specification

## Purpose

A regression test that enforces the hexagonal boundary: the domain and
application layers MUST consume infrastructure only through `Ports`. The
guard scans authored `.res`/`.resi` sources and fails on any direct
infrastructure binding reference, preventing silent boundary regressions.

## Ruling record (2026-10-02, plan 053)

Maintainer ruling on the spec-vs-AGENTS disagreement about
application→infrastructure module imports (e.g. `ShellExecutor` importing
`Fetcher`/`PathSecurity`/`ShellBuilder`/`EnvFilter`, `EngineHooks` importing
`Hooks`, `EngineOrchestrator` importing `Fetcher`):

- **Ports-only consumption remains the TARGET for both layers.** The
  Purpose above is not weakened.
- **Enforcement is staged.** Today's guard asserts the binding-reference
  requirements below for domain AND application (they hold against real
  sources). Routing application-layer MODULE imports (`Fetcher`, `Hooks`,
  …) behind Ports is deferred to a dedicated Ports-extraction plan (L
  effort; also removes `FetchSecurity_test`'s `globalThis.fetch`
  monkey-patching by providing the injection seam). Until that plan lands,
  `AGENTS.md`'s `application → domain + infrastructure` arrow describes
  current reality and the guard MUST NOT assert module-import routing.
- **Guard amendments landed with this ruling** (implementation parity, see
  the guard test): scans cover `.res` AND `.resi`; a missing or unreadable
  scan root FAILS the guard (never a vacuous pass); the domain pattern set
  includes raw Node FFI imports (`@module("node:`) in addition to the
  named binding patterns below; and a fixture-based self-test proves the
  scanner detects planted violations in both file kinds (anti-regression
  tripwire). The `src/domain/template/Frontmatter.res` raw `node:path` FFI
  that motivated the raw-FFI pattern was fixed by threading `Ports.path`.

## Requirements

### Requirement: Domain Layer Isolation

Authored sources under `src/domain/**/*.res` (and `.resi`) MUST NOT contain
direct references to infrastructure bindings. The architecture-guard test
SHALL assert zero matches for each of the patterns `Bindings\.[A-Z]`,
`NodeJs\.[A-Z]`, and `Deno\.[A-Z]`.

#### Scenario: No Bindings references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `Bindings\.[A-Z]`
- THEN zero matches are found

#### Scenario: No NodeJs references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `NodeJs\.[A-Z]`
- THEN zero matches are found

#### Scenario: No Deno references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `Deno\.[A-Z]`
- THEN zero matches are found

### Requirement: Application Layer Isolation

Authored sources under `src/application/**/*.res` (and `.resi`) MUST NOT
contain direct references to infrastructure bindings. The architecture-guard
test SHALL assert zero matches for each of the patterns `Bindings\.[A-Z]`,
`NodeJs\.[A-Z]`, and `Deno\.[A-Z]`.

#### Scenario: No Bindings references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `Bindings\.[A-Z]`
- THEN zero matches are found

#### Scenario: No NodeJs references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `NodeJs\.[A-Z]`
- THEN zero matches are found

#### Scenario: No Deno references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `Deno\.[A-Z]`
- THEN zero matches are found

### Requirement: Infrastructure Layer Exemption

The `src/infrastructure/**/*.res` sources are the designated home for
runtime bindings and adapters. The architecture guard MUST exclude this
tree from its isolation assertions, so legitimate adapter code is not
flagged.

#### Scenario: Infrastructure is not scanned

- GIVEN the architecture-guard test configuration
- WHEN it enumerates scanned directories
- THEN `src/infrastructure/**` is excluded from the domain/application assertions

### Requirement: EJS Direct-Binding Isolation

Authored sources under `src/domain/**/*.res` and `src/application/**/*.res`
(and `.resi`) MUST NOT contain direct references to the EJS infrastructure
binding. The architecture-guard test SHALL assert zero matches for the pattern
`Ejs\.[A-Z]` across both trees. The `src/infrastructure/**` exemption continues
to apply; the sanctioned route for application-layer EJS rendering is the
`Ports.ejs` port (see *Prompt Evaluation EJS Routing*), not the bare binding.

#### Scenario: No Ejs references in application

- GIVEN the architecture-guard test running against `src/application/**/*.res`
- WHEN it scans for `Ejs\.[A-Z]`
- THEN zero matches are found

#### Scenario: No Ejs references in domain

- GIVEN the architecture-guard test running against `src/domain/**/*.res`
- WHEN it scans for `Ejs\.[A-Z]`
- THEN zero matches are found

#### Scenario: Guard fails on a bare Ejs.render leak

- GIVEN `src/application/prompts/EjsSafety.res` still contains a bare
  `Ejs.render(...)` call after the change
- WHEN the architecture-guard test runs against `src/application/**/*.res`
- THEN the `Ejs\.[A-Z]` scan matches the call and the test FAILS
- AND the fix passes only because the bare call has been routed through the port

#### Scenario: Existing isolation assertions remain green

- GIVEN the extended architecture-guard test
- WHEN it runs against `src/domain/**` and `src/application/**`
- THEN the pre-existing `Bindings\.[A-Z]`, `NodeJs\.[A-Z]`, and `Deno\.[A-Z]`
  assertions still report zero matches

### Requirement: Prompt Evaluation EJS Routing

Prompt evaluation in the application layer SHALL render EJS exclusively through
the injected `Ports.ejs` port, never the bare infrastructure binding.
`EjsSafety._renderEval` SHALL accept `~ejs: Ports.ejs` and call
`ejs.renderString(~template, ~context)`. The `~ejs` port SHALL be threaded
through `Expression.evalTemplate`, `_evaluateWhen`, `_evaluateDefault`,
`_evaluateOptions`, `PromptResolver.evalTemplate`, and
`Resolver.resolve`/`processPrompt`/`processPromptBody`, and SHALL originate
from `Ports.deps.ejs` at the pipeline entry that owns `deps` (Phase0 prompt
resolution). `PromptResolver.resi` SHALL declare the updated `~ejs` signatures
for both `evalTemplate` and `resolve`. The `Obj.magic` cast between the
structural eval context and the port's `dict<string>` parameter SHALL remain at
the single `_renderEval` boundary.

#### Scenario: _renderEval renders via the injected port

- GIVEN `EjsSafety._renderEval` called with a valid template and `~ejs` backed
  by a real EJS adapter
- WHEN rendering executes
- THEN it returns `Ok(rendered)` with the template content interpolated
- AND no bare `Ejs.` call is made inside `EjsSafety.res`

#### Scenario: Structural eval context is preserved

- GIVEN `Expression.evalTemplate` called with a template referencing
  `context.<key>` and `answers.<key>`
- WHEN rendering executes against the `{context, answers}` structural context
- THEN the output substitutes both `context.<key>` and `answers.<key>` correctly
- AND `_buildEvalContext` still returns `{context: dict<string>, answers: dict<string>}`
  (not a flattened `dict<string>`)

#### Scenario: Missing ejs argument is a compile-time error

- GIVEN `PromptResolver.resi` declares `evalTemplate` and `resolve` with
  `~ejs: Ports.ejs`
- WHEN a caller omits `~ejs`
- THEN the ReScript compiler rejects the call at compile time

#### Scenario: Error path is result-based

- GIVEN `ejs.renderString` returns `Error(msg)` for a malformed template
- WHEN `Expression.evalTemplate` handles the result
- THEN it surfaces an `Error` (result-matching), not a thrown `JsExn`

### Requirement: EJS Test Fixture Delegation

The prompt-evaluation test fixtures SHALL construct an `ejs` stub that
delegates to the real EJS binding so nested `context`/`answers` key resolution
is exercised identically to production. `TestPorts.stubEjs.renderString` SHALL
delegate to `Bindings.Ejs.render`, mirroring how `stubYamlParser` delegates to
`Bindings.Yaml.parse`. A no-op stub that returns `Ok(template)` unmodified is
PROHIBITED — it masks structural-context regressions.

#### Scenario: stubEjs delegates to the real binding

- GIVEN `test/res/utils/TestPorts.res` provides `stubEjs`
- WHEN `stubEjs.renderString` runs against a template interpolating
  `context.<key>`
- THEN it returns the substituted output, not the raw template

#### Scenario: Affected tests inject the ejs port

- GIVEN `test/PromptResolver_test.res` and `test/Phase0Integration_test.res`
- WHEN they invoke `evalTemplate` or `resolve`
- THEN they pass `~ejs=TestPorts.stubEjs`
