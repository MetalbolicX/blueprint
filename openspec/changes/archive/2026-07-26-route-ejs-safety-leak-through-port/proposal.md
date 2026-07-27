# Proposal: Route EjsSafety EJS leak through Ports.ejs

## Intent

`src/application/prompts/EjsSafety.res:19` calls bare `Ejs.render(template, ctx->Obj.magic)`, which resolves via ReScript module resolution to the infrastructure binding `src/infrastructure/bindings/Ejs.res`. The application layer touches infrastructure directly — a hexagonal leak the current `ArchitectureGuard_test.res` does **not** catch: its `checkLine` only forbids `Bindings.`/`NodeJs.`/`Deno.`, and bare `Ejs.` escapes that set. Route the call through the existing `Ports.ejs.renderString` port and harden the guard so the leak cannot regress.

## Scope

### In Scope
- `_renderEval` calls `ejs.renderString` instead of bare `Ejs.render`.
- Thread `~ejs: Ports.ejs` through `evalTemplate` + the 3 helpers + the `resolve` chain.
- Extend `ArchitectureGuard_test.res` `checkLine` to forbid `Ejs.` in domain/application.
- Fix `TestPorts.stubEjs` to delegate to the real binding (mirror `stubYamlParser`).
- Update affected tests to pass `~ejs`.

### Out of Scope
- Changing `_buildEvalContext` shape — `{context, answers}` stays structural; **must NOT** be flattened to `dict<string>` (this is what regressed 5 tests last time).
- Adding new ports — `Ports.ejs` already exists.
- Node/Deno adapter changes — both already satisfy the port.

## Capabilities

> Contract for sdd-spec. Existing specs audited under `openspec/specs/` (`architecture-guard`, `ports`).

### New Capabilities
None.

### Modified Capabilities
- `architecture-guard`: the guard SHALL additionally assert zero `Ejs.` references across `src/domain/**` and `src/application/**`, and SHALL codify that prompt evaluation routes EJS rendering through `Ports.ejs.renderString` (not the bare binding).

## Approach

Full dependency-injection thread-through. `Ports.deps.ejs` is already bundled at the composition root, so the engine passes `~ejs` down `resolve` → `processPrompt`/`processPromptBody` → helpers → `evalTemplate` → `_renderEval` → `ejs.renderString`.

Two boundary details the design must pin:
1. The `Obj.magic` cast stays at the `_renderEval` boundary: the port's `renderString(~context: dict<string>)` is typed `dict<string>` but the eval context is a structural `{context, answers}` object. The cast bridges that (same as today); the structural shape is preserved.
2. The port returns `result<string,string>`; `evalTemplate` switches its error path from `try/catch JsExn` to result-matching.

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `src/application/prompts/EjsSafety.res` | Modified | `_renderEval` gains `~ejs`, calls `ejs.renderString`; reword the `Ejs.render` comment to avoid `Ejs.` substring false-positive |
| `src/application/prompts/Expression.res` | Modified | `evalTemplate` + `_evaluateWhen`/`_evaluateDefault`/`_evaluateOptions` gain `~ejs` |
| `src/application/prompts/Resolver.res` | Modified | `processPromptBody`/`processPrompt`/`resolve` thread `~ejs` (4 callsites) — **beyond original 5-file list** |
| `src/application/prompts/PromptResolver.res` + `.resi` | Modified | re-exported `evalTemplate` and `resolve` gain `~ejs` |
| engine/pipeline caller of `resolve` | Modified | passes `~ejs` from `deps.ejs` |
| `test/res/utils/TestPorts.res` | Modified | `stubEjs` delegates to `Bindings.Ejs.render` (was a no-op `Ok(template)`) |
| `test/PromptResolver_test.res` | Modified | `evalTemplate`/`resolve` callsites pass `~ejs` |
| `test/ArchitectureGuard_test.res` | Modified | `checkLine` adds `Ejs.` |

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Flattening `_buildEvalContext` to `dict<string>` (broke 5 tests last attempt) | Med | Spec pins `{context, answers}` shape; stub delegates to real EJS so nested `context.foo`/`answers.bar` actually render |
| `Ejs.` guard false-positive on the EjsSafety comment text | Med | Reword comment to drop the `Ejs.` substring |
| Cascade touches more files than the original 5-file list | High | Confirmed via grep: `Resolver.res` + engine caller required (see Affected Areas) |
| Error-path shape change (result vs exception) subtly alters failure messages | Low | Map `Error(msg)` into existing `EvaluationError`; keep message extraction parity |

## Rollback Plan

Revert the modified files; `_renderEval` returns to bare `Ejs.render`. The `ArchitectureGuard_test.res` extension is independently revertible. No data or config migrations are involved, so rollback is a pure `git revert` of the change set.

## Dependencies

- `Ports.ejs` (`renderString`/`renderFile`) — already present (`src/domain/ports/Ports.res:24`).
- `Ports.deps.ejs` bundle field — already wired at the composition root.
- `TestPorts.stubEjs` — exists; needs the delegation fix.

## Success Criteria

- [ ] `pnpm res:test` green, including the 5 tests that regressed in the prior reverted attempt.
- [ ] `ArchitectureGuard_test.res` **fails** if any `Ejs.` reference appears under `src/domain` or `src/application` (proven by a deliberate temporary violation).
- [ ] `EjsSafety.res` contains no bare `Ejs.render` call.
- [ ] `_buildEvalContext` still returns `{context: dict<string>, answers: dict<string>}` (structural, not flattened).
- [ ] `pnpm build` succeeds.
