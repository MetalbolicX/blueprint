# Design: Route EjsSafety EJS through Ports.ejs

## Technical Approach

Inject the existing `Ports.ejs` capability from the composition root through
the complete Phase 0 prompt-resolution chain. `EjsSafety` becomes the only
render boundary; `Expression`, `Resolver`, `Phase0`, and `EnginePhases` only
forward the dependency. Preserve `_buildEvalContext` as the structural
`{context, answers}` object and convert only at `_renderEval`. Map the port's
`result<string, string>` directly into the existing `EvaluationError` path.

```text
deps.ejs → EnginePhases.runPhase0 → Phase0.run → Resolver.resolve
         → processPrompt/body → Expression helpers → evalTemplate
         → EjsSafety._renderEval → ejs.renderString
```

## Architecture Decisions

| Decision | Choice | Alternatives rejected | Rationale |
|---|---|---|---|
| Dependency routing | Thread labeled `~ejs` through every layer | Keep a direct binding or global lookup | Preserves the hexagonal boundary and makes the dependency explicit and testable. |
| Eval-context bridge | Keep `{context, answers}`; localize JSON conversion in `_renderEval` | Flatten the dictionaries; serialize in callers; `JSON.Encode.object_` | Flattening breaks nested EJS expressions. `%raw(JSON.stringify(ctx))` works for any structural JS object and keeps the untyped boundary in one named helper. |
| Fixture behavior | `stubEjs.renderString` delegates to `Bindings.Ejs.render` and catches `JsExn` | `Ok(template)` no-op | Real interpolation is required to detect `context.*`/`answers.*` regressions. |
| Guard | Extend `checkLine` with `Ejs.` and rename both assertions | Rely on code review | The regression test must reject the exact bare-binding leak. Reword the `EjsSafety` comment so `Ejs.` does not self-trigger. |

The `_renderEval` implementation is planned as:

```rescript
let _renderEval: (~ejs: Ports.ejs, ~template: string, ~ctx: {..}) => result<string, string> =
  (~ejs, ~template, ~ctx) => {
    let ctxJson: string = %raw(`JSON.stringify(ctx)`)
    let ctxDict: dict<string> = Dict.make()
    Dict.set(ctxDict, "ctx", ctxJson)
    ejs.renderString(~template, ~context=ctxDict)
  }
```

Any required `Obj.magic` stays at this single boundary; no caller flattens or
reconstructs the evaluation context.

## File Changes

| Tier / file | Action |
|---|---|
| 1 `src/application/prompts/EjsSafety.res` | Change `_renderEval` to accept `~ejs`, perform the context bridge, and return a result. |
| 2 `src/application/prompts/Expression.res` | Add `~ejs` to `evalTemplate` and `_evaluateWhen`, `_evaluateDefault`, `_evaluateOptions`; switch rendering errors to result matching. |
| 3 `src/application/prompts/PromptResolver.res` | Preserve re-exports while exposing the updated inferred functions. |
| 3 `src/application/prompts/PromptResolver.resi` | Declare `~ejs: Ports.ejs` on `evalTemplate` and `resolve`. |
| 4 `src/application/prompts/Resolver.res` | Thread `~ejs` through `resolve`, `processPrompt`, and `processPromptBody`, including all helper calls. |
| 5 `src/application/pipeline/Phase0.res` / `.resi` | Accept `~ejs` and pass it to `resolve`. |
| 6 `src/application/engine/EnginePhases.res` / `.resi` | Accept `~ejs` on `runPhase0` and pass it to `Phase0.run`. |
| 6 `src/application/engine/EngineOrchestrator.res` | Pass destructured `deps.ejs` to `runPhase0`; its `.resi` remains unchanged because `run(~deps)` already exposes the bundle. |
| Tests | Update `test/res/utils/TestPorts.res`, all `PromptResolver_test.res` calls, all `Phase0Integration_test.res` calls, and `ArchitectureGuard_test.res`. |

Test fixture implementation mirrors `stubYamlParser`: wrap
`Bindings.Ejs.render(template, context->Obj.magic)` in `Ok`, catch `JsExn`,
and return its message. There is no `TestPorts.resi` or prompt-module `.resi`
other than `PromptResolver.resi`.

## Interfaces / Contracts

All new labels use `~ejs: Ports.ejs`. `Ports.ejs.renderString` remains
`(~template: string, ~context: dict<string>) => result<string, string>`;
`_buildEvalContext` remains `{context: dict<string>, answers: dict<string>}`.
The guard checks `Bindings.`, `NodeJs.`, `Deno.`, and `Ejs.`.

## Testing Strategy

| Layer | Coverage |
|---|---|
| Unit | Real-stub interpolation, nested `context`/`answers`, unsafe tags, malformed-template result errors, and compile-time labels. |
| Integration | Phase 0 resolution/conflict tests with `~ejs=TestPorts.stubEjs`; full `pnpm res:test`. |
| Build | `pnpm build` verifies every `.resi` contract and the bundle. |

## Threat Matrix

| Boundary | Applicability |
|---|---|
| Documentation-like paths | N/A — no executable-file classification. |
| Git repository selection | N/A — no VCS automation. |
| Commit state | N/A — no commit operation. |
| Push state | N/A — no push operation. |
| PR commands | N/A — no PR automation. |

No shell, subprocess, or process-integration boundary changes.

## Migration / Rollout

No migration required; this is an internal dependency-routing change.

## Open Questions

None. Ready for `sdd-tasks` in the listed dependency order; begin with the
real-rendering test stub, then production thread-through, call-site updates,
guard assertions, and build/test verification.
