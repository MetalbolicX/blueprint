# Tasks: Route EjsSafety EJS through Ports.ejs

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | 180-260 |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single commit after final verification |
| Delivery strategy | ask-on-risk (default) |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low
Threat matrix: all rows are N/A; no shell, VCS, push, or PR RED task applies.

### Suggested Work Units

| Unit | Goal | Likely PR | Focused test command | Runtime harness | Rollback boundary |
|------|------|-----------|----------------------|-----------------|-------------------|
| 1 | Complete the port-routed prompt chain | Single | `pnpm res:test` | `pnpm res:build` + test runner | Revert all listed source/test edits |

## Phase 1: Render Boundary

- [x] **1.1 TestPorts stub** — **Files:** `test/res/utils/TestPorts.res` (no `.resi` exists). **Accept:** try/catch delegates `stubEjs.renderString` to `Bindings.Ejs.render`; interpolation is substituted. **Risk:** Low. **Depends:** none.
- [x] **1.2 EjsSafety boundary** — **Files:** `src/application/prompts/EjsSafety.res`. **Accept:** `_renderEval(~ejs)` calls `ejs.renderString` with `Obj.magic` cast on the structural context; no bare binding text. **Risk:** Medium. **Depends:** 1.1.

## Phase 2: Expression and Public API

- [x] **2.1 Expression threading** — **Files:** `src/application/prompts/Expression.res`. **Accept:** four helpers accept/forward `~ejs`; result errors remain `EvaluationError`; `_buildEvalContext` stays `{context, answers}` (spec scenarios). **Risk:** High. **Depends:** 1.2.
- [x] **2.2 PromptResolver contract** — **Files:** `src/application/prompts/PromptResolver.res`, `src/application/prompts/PromptResolver.resi`. **Accept:** aliases and declared `evalTemplate`/`resolve` signatures require `~ejs`; omitted labels fail compilation. **Risk:** Medium. **Depends:** 2.1.

## Phase 3: Resolver and Pipeline Wiring

- [x] **3.1 Resolver propagation** — **Files:** `src/application/prompts/Resolver.res`. **Accept:** `resolve`, `processPrompt`, and `processPromptBody` thread `~ejs` through every evaluation helper. **Risk:** Medium. **Depends:** 2.2.
- [x] **3.2 Phase0 propagation** — **Files:** `src/application/pipeline/Phase0.res`, `src/application/pipeline/Phase0.resi`. **Accept:** `run(~ejs)` forwards the port to `Resolver.resolve`. **Risk:** Low. **Depends:** 3.1.
- [x] **3.3 Engine phase propagation** — **Files:** `src/application/engine/EnginePhases.res`, `src/application/engine/EnginePhases.resi`. **Accept:** `runPhase0(~ejs)` forwards it to `Phase0.run`. **Risk:** Low. **Depends:** 3.2.
- [x] **3.4 Composition-root origin** — **Files:** `src/application/engine/EngineOrchestrator.res`. **Accept:** destructured `deps.ejs` reaches `EnginePhases.runPhase0`; public `EngineOrchestrator.resi` remains unchanged. **Risk:** Low. **Depends:** 3.3.

## Phase 4: Call Sites and Guard

- [x] **4.1 Test call sites** — **Files:** `test/PromptResolver_test.res`, `test/Phase0Integration_test.res` (all 3 eval, 20 resolve, and 5 Phase0 calls). **Accept:** every call injects `~ejs=TestPorts.stubEjs`; simple interpolation and integration scenarios pass. **Risk:** Medium. **Depends:** 3.4.
- [x] **4.2 Architecture guard** — **Files:** `test/ArchitectureGuard_test.res`. **Accept:** `checkLine` rejects `Ejs.` alongside existing patterns; names/description include Ejs; both layer scans pass (spec: no-Ejs and leak-failure scenarios). **Risk:** Low. **Depends:** 1.2.

## Phase 5: Verification

- [x] **5.1 Build and regression run** — **Files:** none (verification only). **Accept:** `pnpm res:build` is clean; `pnpm res:test` reports 625/627 passing with only the same two pre-existing failures, and both architecture-guard tests pass. **Risk:** Medium. **Depends:** 4.1, 4.2.
